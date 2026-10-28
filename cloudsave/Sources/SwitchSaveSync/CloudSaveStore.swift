import Foundation

public enum CloudSavePreferences {
    public static let container = "iCloud.com.odestins.iswitch"
    public static let enabledKey = "switch.cloudSaves.enabled"
    public static var configured: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "DMCloudSaveEnabled")
        return (value as? Bool) == true || ["YES", "true", "1"].contains(value as? String ?? "")
    }
    public static var enabled: Bool {
        get { configured && ((NSUbiquitousKeyValueStore.default.object(forKey: enabledKey) as? Bool) ?? true) }
        set { guard configured else { return }; NSUbiquitousKeyValueStore.default.set(newValue, forKey: enabledKey); NSUbiquitousKeyValueStore.default.synchronize() }
    }
}

public struct CloudSaveRecord: Identifiable, Sendable, Equatable {
    public var manifest: SaveManifest
    public var url: URL
    public var uploaded: Bool
    public var id: String { manifest.id }
}

public struct SaveLocalState: Codable, Sendable {
    public var clock = SaveClock()
    public var contentHash = ""
    public var device = UUID().uuidString.lowercased()
    public var lastQueued: Date?
}

/// All hashing, coordinated file access, and archive work runs off the UI actor.
/// Local saves remain authoritative while a game is running. Only the pre-boot
/// gate may restore; receiving an iCloud update never edits an open save tree.
public actor CloudSaveStore {
    private let directory: URL
    private var state: SaveLocalState
    private let titleID: String
    private let game: String
    private let version: String
    private let deviceName: String
    private let cloudRoot: @Sendable () -> URL?
    private let isEnabled: @Sendable () -> Bool
    private var pending: URL { directory.appendingPathComponent("outbox.switchsave") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    public init(directory: URL, titleID: String, game: String, version: String, deviceName: String,
                cloudRoot: @escaping @Sendable () -> URL? = { CloudSaveStore.containerURL() },
                isEnabled: @escaping @Sendable () -> Bool = { CloudSavePreferences.enabled }) throws {
        self.directory = directory; self.titleID = titleID; self.game = game; self.version = version; self.deviceName = String(deviceName.prefix(128))
        self.cloudRoot = cloudRoot; self.isEnabled = isEnabled
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        // Never silently reset a damaged causal history: it could mistake an
        // older remote save for a safe replacement of current local progress.
        if FileManager.default.fileExists(atPath: url.path) {
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let bytes = try file.read(upToCount: 64 * 1024 + 1) ?? Data()
            guard bytes.count <= 64 * 1024 else { throw SaveError.invalid("The local save history is too large to read safely. Your progress and recovery files were kept.") }
            state = try JSONDecoder().decode(SaveLocalState.self, from: bytes)
            try Self.validate(state)
        }
        else {
            // Persist identity before the first outbox, so an interrupted first
            // checkpoint still belongs to the same local history on relaunch.
            state = SaveLocalState()
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        }
    }
    public func localState() throws -> SaveLocalState { try recoverPending(); return state }

    public static func containerURL() -> URL? {
        guard CloudSavePreferences.configured, FileManager.default.ubiquityIdentityToken != nil else { return nil }
        return FileManager.default.url(forUbiquityContainerIdentifier: CloudSavePreferences.container)
    }
    public static func readRecords(_ urls: [URL]) -> [CloudSaveRecord] {
        readRecords(urls, load: readRecord)
    }

    /// Metadata notifications can supersede a scan while it is coordinating a
    /// file. Check cancellation between files so obsolete scans stop doing I/O.
    static func readRecords(_ urls: [URL], load: (URL) -> CloudSaveRecord?) -> [CloudSaveRecord] {
        var records: [CloudSaveRecord] = []
        for url in urls.prefix(512) {
            guard !Task.isCancelled else { return [] }
            if let record = load(url) { records.append(record) }
        }
        guard !Task.isCancelled else { return [] }
        return records.sorted { $0.manifest.savedAt > $1.manifest.savedAt }
    }

    private static func readRecord(_ url: URL) -> CloudSaveRecord? {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey])
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try FileManager.default.startDownloadingUbiquitousItem(at: url); return nil
            }
            var manifest: SaveManifest?, failure: Error?
            var coordination: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { coordinated in
                do { manifest = try SaveArchive.readManifest(coordinated) } catch { failure = error }
            }
            if failure == nil, coordination == nil, let manifest {
                return CloudSaveRecord(manifest: manifest, url: url, uploaded: values.ubiquitousItemIsUploaded == true)
            }
        } catch { /* A pending download is retried by the metadata query. */ }
        return nil
    }

    public func submit(snapshot: URL) throws {
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try Task.checkCancellation()
        guard isEnabled() else { return }
        try recoverPending()
        let entries = try SaveArchive.entries(at: snapshot)
        guard entries.contains(where: { !$0.directory }) else { return }
        let hash = try SaveArchive.fingerprint(entries)
        if state.contentHash != hash {
            var next = state; try next.clock.advance(device: next.device)
            let manifest = SaveManifest(titleID: titleID, game: game, version: version, device: next.device, deviceName: deviceName, clock: next.clock)
            let archive = directory.appendingPathComponent(UUID().uuidString + ".switchsave")
            defer { try? FileManager.default.removeItem(at: archive) }
            let finished = try SaveArchive.write(snapshot: snapshot, to: archive, manifest: manifest, entries: entries)
            // Publish the recoverable outbox before advancing local history.
            // A crash between these steps is reconciled from its manifest below.
            if FileManager.default.fileExists(atPath: pending.path) { _ = try FileManager.default.replaceItemAt(pending, withItemAt: archive) }
            else { try FileManager.default.moveItem(at: archive, to: pending) }
            next.contentHash = finished.contentHash; next.lastQueued = finished.savedAt
            try persist(next); state = next
        }
        try publishPending()
    }

    public func publishPending() throws {
        guard isEnabled(), let manifest = try recoverPending() else { return }
        guard !state.clock.dominates(manifest.clock) || state.clock == manifest.clock else { return }
        guard let root = cloudRoot() else { throw SaveError.unavailable }
        let folder = root.appendingPathComponent("Documents/Saves", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("\(titleID)-\(manifest.id).switchsave")
        var coordination: NSError?, failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordination) { url in
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    let staging = folder.appendingPathComponent(".upload-\(titleID)-\(state.device).partial")
                    // A process killed during copy cannot publish a valid-looking
                    // header with an incomplete payload at the final filename.
                    try? FileManager.default.removeItem(at: staging)
                    defer { try? FileManager.default.removeItem(at: staging) }
                    try FileManager.default.copyItem(at: pending, to: staging)
                    try FileManager.default.moveItem(at: staging, to: url)
                }
                else if try SaveArchive.readManifest(url) != manifest { throw SaveError.invalid("A different save occupies the backup location.") }
                guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == pending.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw SaveError.invalid("The queued backup is incomplete. Its local recovery copy was kept.") }
            } catch { failure = error }
        }
        if let error = coordination ?? failure as NSError? { throw error }
        // Keep the outbox until a later checkpoint replaces it. A successful local
        // copy only queues an upload; it does not prove the server has the bytes.
        try pruneHistory(in: folder, newest: manifest)
    }

    @discardableResult private func recoverPending() throws -> SaveManifest? {
        guard FileManager.default.fileExists(atPath: pending.path) else { return nil }
        let manifest = try SaveArchive.readManifest(pending)
        guard manifest.titleID == titleID, manifest.device == state.device else { throw SaveError.invalid("The pending backup does not match this game.") }
        if manifest.clock != state.clock, manifest.clock.dominates(state.clock) {
            var recovered = state; recovered.clock = manifest.clock; recovered.contentHash = manifest.contentHash; recovered.lastQueued = manifest.savedAt
            try persist(recovered); state = recovered
        }
        return manifest
    }

    private func pruneHistory(in folder: URL, newest: SaveManifest) throws {
        // Keep three server-confirmed revisions from this installation. Never
        // delete another device's progress or concurrent heads. Superseded
        // pending uploads can be coalesced because the newest complete archive
        // and the persistent local outbox both already contain their successor.
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.ubiquitousItemIsUploadedKey])
            .filter { $0.lastPathComponent.hasPrefix(titleID + "-") && $0.pathExtension == "switchsave" }
        let own = Self.readRecords(urls).filter { $0.manifest.device == state.device && $0.manifest.titleID == titleID }
            .sorted { $0.manifest.clock.values[state.device, default: 0] > $1.manifest.clock.values[state.device, default: 0] }
        let keepUploaded = Set(own.filter(\.uploaded).prefix(3).map(\.id))
        for record in own where record.id != newest.id && !keepUploaded.contains(record.id) && newest.clock != record.manifest.clock && newest.clock.dominates(record.manifest.clock) {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: record.url, options: .forDeleting, error: &error) { try? FileManager.default.removeItem(at: $0) }
        }
    }

    public func restore(record: CloudSaveRecord, save: URL, backups: URL) throws {
        guard record.manifest.titleID == titleID else { throw SaveError.invalid("Choose a save for this game.") }
        var coordination: NSError?, failure: Error?, restored: SaveManifest?
        NSFileCoordinator().coordinate(readingItemAt: record.url, options: [], error: &coordination) { url in
            do { restored = try SaveArchive.restore(url, save: save, backups: backups, titleID: titleID, expectedManifest: record.manifest) } catch { failure = error }
        }
        if let error = coordination ?? failure as NSError? { throw error }
        guard let restored else { throw SaveError.invalid("The cloud save could not be restored.") }
        var next = state
        // A deliberate conflict choice acknowledges every head shown by the UI
        // through acknowledge(), then publishes a new revision on the next save.
        // Restoring older content must not rewind this installation's counter.
        // Its next revision represents a deliberate new choice, otherwise a
        // previously uploaded later checkpoint would immediately win again.
        next.clock = next.clock.merged(restored.clock); next.contentHash = restored.contentHash
        try persist(next); state = next
        try? FileManager.default.removeItem(at: pending)
    }
    public func acknowledge(_ clocks: [SaveClock]) throws {
        var next = state
        for clock in clocks { next.clock = next.clock.merged(clock) }
        // Force the chosen content to publish a new revision, even unchanged.
        next.contentHash = ""; try persist(next); state = next
    }
    public func adoptMatching(_ manifest: SaveManifest, localHash: String) throws {
        guard manifest.titleID == titleID, manifest.contentHash == localHash else { return }
        var next = state; next.clock = next.clock.merged(manifest.clock); next.contentHash = localHash
        try persist(next); state = next
    }
    public static func localFingerprint(_ save: URL) throws -> (String, Bool) {
        guard FileManager.default.fileExists(atPath: save.path) else { return ("", false) }
        let entries = try SaveArchive.entries(at: save)
        return (try SaveArchive.fingerprint(entries), entries.contains { !$0.directory })
    }
    private func persist(_ value: SaveLocalState) throws {
        try Self.validate(value)
        try JSONEncoder().encode(value).write(to: stateURL, options: .atomic)
    }

    private static func validate(_ value: SaveLocalState) throws {
        guard UUID(uuidString: value.device) != nil, value.clock.values.count <= 64,
              value.clock.values.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value > 0 }),
              value.contentHash.isEmpty || value.contentHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw SaveError.invalid("The local save history is damaged. Your progress and recovery files were kept.")
        }
    }
}
