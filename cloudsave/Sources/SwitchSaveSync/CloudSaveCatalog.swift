import Foundation
import Combine

@MainActor public final class CloudSaveCatalog: ObservableObject {
    @Published public private(set) var records: [CloudSaveRecord] = []
    @Published public private(set) var status = "Checking iCloud…"
    @Published public private(set) var available = false
    @Published public private(set) var gathering = false
    @Published public private(set) var hasFinishedScan = false
    @Published public var enabled = CloudSavePreferences.enabled
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var generation = 0
    private var root: URL?

    public init() {}
    public func setEnabled(_ value: Bool) { enabled = value; CloudSavePreferences.enabled = value }
    public func start() async {
        guard CloudSavePreferences.configured else {
            available = false; gathering = false; status = "Requires an iCloud-enabled app update. Your saves remain on this iPhone."; return
        }
        enabled = CloudSavePreferences.enabled
        NSUbiquitousKeyValueStore.default.synchronize()
        if query != nil { reload(); return }
        guard startTask == nil else { return }
        if observers.isEmpty {
            observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop(); self?.records = []; await self?.start() }
            })
        }
        gathering = true; hasFinishedScan = false; status = "Checking iCloud…"
        let current = generation
        // Resolving the container can block in Apple's filesystem service.
        // The boot gate can stop waiting without starting a late restore/query.
        startTask = Task { [weak self] in
            let container = await Task.detached(priority: .utility) { CloudSaveStore.containerURL() }.value
            guard !Task.isCancelled, let self, generation == current else { return }
            startTask = nil
            guard let container else { available = false; gathering = false; hasFinishedScan = true; status = "Sign in to iCloud and enable iCloud Drive in iPhone Settings."; return }
            beginQuery(container)
        }
    }
    private func beginQuery(_ container: URL) {
        root = container; available = true
        let query = NSMetadataQuery(); query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, ".switchsave")
        query.notificationBatchingInterval = 1
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, NSNotification.Name.NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.gathering = false; self?.reload() }
            })
        }
        self.query = query
        if !query.start() { stop(); status = "iCloud could not be checked. Try again."; available = false; hasFinishedScan = true }
    }
    public func reload() {
        guard let query, let root else { return }
        query.disableUpdates()
        let folder = root.appendingPathComponent("Documents/Saves").resolvingSymlinksInPath().path + "/"
        let items = query.results.compactMap { $0 as? NSMetadataItem }.sorted {
            ($0.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast) > ($1.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast)
        }
        let urls = items.compactMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }.filter { $0.resolvingSymlinksInPath().path.hasPrefix(folder) }
        query.enableUpdates()
        generation += 1; let current = generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let rows = await Task.detached(priority: .utility) { CloudSaveStore.readRecords(urls) }.value
            guard !Task.isCancelled, let self, generation == current else { return }
            if records != rows { records = rows }
            hasFinishedScan = true
            status = rows.isEmpty ? (urls.isEmpty ? "Ready for your first game save" : "Downloading save information…") : rows.contains(where: { !$0.uploaded }) ? "Waiting for iCloud upload" : "Saves are in iCloud"
        }
    }
    public func stop() {
        generation += 1; startTask?.cancel(); startTask = nil; refreshTask?.cancel(); refreshTask = nil; query?.stop(); query = nil; gathering = false
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
    }
    deinit { query?.stop(); observers.forEach(NotificationCenter.default.removeObserver); startTask?.cancel(); refreshTask?.cancel() }
}
