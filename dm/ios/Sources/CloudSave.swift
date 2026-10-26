import Foundation
import UIKit
import SwitchSaveSync
import Darwin

// A commit arrives while the host's save mutex is held. Clone only the committed
// directory here (APFS copy-on-write); hashing and iCloud access happen later.
// At most one active clone and one newest waiting clone are retained.
private final class SaveCaptureQueue: @unchecked Sendable {
    static let shared = SaveCaptureQueue()
    private let lock = NSLock()
    private var store: CloudSaveStore?
    private var save: URL?
    private var directory: URL?
    private var pending: URL?
    private var running = false

    func configure(store: CloudSaveStore, save: URL, directory: URL) {
        lock.lock(); defer { lock.unlock() }; self.store = store; self.save = save; self.directory = directory
    }
    func capture(_ path: String) {
        guard CloudSavePreferences.enabled else { return }
        lock.lock(); defer { lock.unlock() }
        guard let save, let directory, store != nil, URL(fileURLWithPath: path).standardizedFileURL == save.standardizedFileURL else { return }
        let snapshot = directory.appendingPathComponent("capture-\(UUID().uuidString)")
        guard clonefile(save.path, snapshot.path, 0) == 0 else { fputs("cloud save: local checkpoint clone failed; game save is unchanged\n", stderr); return }
        if let old = pending { try? FileManager.default.removeItem(at: old) }
        pending = snapshot
        if !running { running = true; Task.detached(priority: .utility) { await self.drain() } }
    }
    private func next() -> (URL, CloudSaveStore)? {
        lock.lock(); defer { lock.unlock() }
        guard let url = pending, let store else { running = false; return nil }
        pending = nil; return (url, store)
    }
    private func drain() async {
        while let (url, store) = next() {
            do { try await store.submit(snapshot: url); fputs("cloud save: checkpoint queued for iCloud\n", stderr) }
            catch { fputs("cloud save: \(error.localizedDescription)\n", stderr) }
        }
    }
}

@_cdecl("dm_cloud_save_committed")
public func dmCloudSaveCommitted(_ path: UnsafePointer<CChar>) { SaveCaptureQueue.shared.capture(String(cString: path)) }

@MainActor private enum CloudBoot {
    static var started = false
    static var requested: String?
}

@_cdecl("dm_cloud_request_restore")
@MainActor public func dmCloudRequestRestore(_ value: UnsafePointer<CChar>) {
    guard let uuid = UUID(uuidString: String(cString: value)) else { return }
    let id = uuid.uuidString.lowercased()
    UserDefaults.standard.set(id, forKey: "cloudSave.requestedRestore")
    CloudBoot.requested = id
    if CloudBoot.started {
        let alert = UIAlertController(title: "Restore on next launch", message: "Close this game from the app switcher, then open it again. Your current session will keep its progress until you choose the save to restore.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        let root = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        root?.present(alert, animated: true)
    }
}

@_cdecl("dm_cloud_prepare")
@MainActor public func dmCloudPrepare(_ controller: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) -> Bool {
    guard CloudSavePreferences.configured, Bundle.main.object(forInfoDictionaryKey: "DMCloudSaveContainer") as? String == CloudSavePreferences.container,
          let titleID = Bundle.main.object(forInfoDictionaryKey: "DMTitleID") as? String,
          let savePath = getenv("DM_SAVE") else { return false }
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let save = URL(fileURLWithPath: String(cString: savePath)).standardizedFileURL
    // Automated port checks use isolated saves and must never enter iCloud.
    guard save == documents.appendingPathComponent("save").standardizedFileURL else { return false }
    CloudBoot.started = true
    let parent = Unmanaged<UIViewController>.fromOpaque(controller).takeUnretainedValue()
    let label = UILabel(frame: parent.view.bounds)
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; label.textAlignment = .center
    label.text = "Checking saved progress…"; label.textColor = .white; label.font = .preferredFont(forTextStyle: .body)
    parent.view.addSubview(label)
    Task { @MainActor in
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SwitchSaveSync", isDirectory: true)
        let catalog = CloudSaveCatalog()
        defer { catalog.stop(); label.removeFromSuperview() }
        do {
            let game = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? titleID
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
            let name = UIDevice.current.name
            let store = try await Task.detached(priority: .utility) { try CloudSaveStore(directory: directory, titleID: titleID, game: game, version: version, deviceName: name) }.value
            SaveCaptureQueue.shared.configure(store: store, save: save, directory: directory)
            if CloudSavePreferences.enabled {
                await catalog.start()
                let deadline = Date().addingTimeInterval(4)
                while !catalog.hasFinishedScan && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
                let records = catalog.records.filter { $0.manifest.titleID == titleID }
                let requested = CloudBoot.requested ?? UserDefaults.standard.string(forKey: "cloudSave.requestedRestore")
                let state = try await store.localState()
                let local = try await Task.detached(priority: .utility) { try CloudSaveStore.localFingerprint(save) }.value
                var restore: CloudSaveRecord?, acknowledged: [SaveClock] = []
                if let requested {
                    if let record = records.first(where: { $0.id.lowercased() == requested.lowercased() }) {
                        let selected = await chooseSave(parent: parent, localExists: local.1, records: [record], title: "Restore saved progress?")
                        restore = selected; if selected != nil { acknowledged = [record.manifest.clock] }
                        UserDefaults.standard.removeObject(forKey: "cloudSave.requestedRestore"); CloudBoot.requested = nil
                    } else { label.text = "That save is still downloading. Starting with local progress."; try await Task.sleep(for: .seconds(1)) }
                } else {
                    switch SaveResolution.decide(records: records, state: state, localHash: local.0, localExists: local.1, version: version) {
                    case .local: break
                    case .adopt(let manifest): try await store.adoptMatching(manifest, localHash: local.0)
                    case .restore(let record): restore = record
                    case .choose(let choices):
                        let shown = Array(choices.prefix(5))
                        restore = await chooseSave(parent: parent, localExists: local.1, records: shown, title: "Choose your progress")
                        acknowledged = shown.map(\.manifest.clock)
                    }
                }
                if let restore {
                    label.text = "Restoring saved progress…"
                    try await store.restore(record: restore, save: save, backups: documents.appendingPathComponent("Save Backups"))
                }
                if !acknowledged.isEmpty { try await store.acknowledge(acknowledged) }
                // Back up existing progress on first upgrade, and retry an
                // offline outbox. No restore can occur after done starts play.
                if FileManager.default.fileExists(atPath: save.path) { SaveCaptureQueue.shared.capture(save.path) }
            }
        } catch { fputs("cloud save: \(error.localizedDescription); starting with local progress\n", stderr) }
        done()
    }
    return true
}

@MainActor private func chooseSave(parent: UIViewController, localExists: Bool, records: [CloudSaveRecord], title: String) async -> CloudSaveRecord? {
    await withCheckedContinuation { continuation in
        let message = "Your saves have different progress. Choose which to play. Restoring keeps a recovery copy of this iPhone’s save."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for record in records.prefix(5) {
            let m = record.manifest
            let name = "\(m.deviceName) · \(m.savedAt.formatted(date: .abbreviated, time: .shortened)) · v\(m.version)"
            alert.addAction(UIAlertAction(title: name, style: .default) { _ in continuation.resume(returning: record) })
        }
        alert.addAction(UIAlertAction(title: localExists ? "Keep this iPhone’s progress" : "Start on this iPhone", style: .cancel) { _ in continuation.resume(returning: nil) })
        parent.present(alert, animated: true)
    }
}
