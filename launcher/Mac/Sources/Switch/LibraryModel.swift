import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import SwitchMacRuntime
import iSwitchCore

@MainActor
final class MacModel: ObservableObject {
    static let shared = MacModel()
    @Published var games: [PreparedGame] = []
    @Published var selectedID: String?
    @Published var runningID: String?
    @Published var isLaunching = false
    @Published private(set) var isLoading = true
    @Published private(set) var isUpdatingLibrary = false
    @Published var message: String?
    @Published var panel: MacPanel?
    @Published private(set) var covers: [String: NSImage] = [:]
    @Published var photo: NSImage?
    @Published var problems: [String: String] = [:]
    @Published var latestLog: URL?
    @Published var controllerNames: [String] = []
    @Published var focusedDock: Int?
    private var launcherControllers: LauncherControllers?
    func startControllers() { if launcherControllers == nil { launcherControllers = LauncherControllers(model: self) } }
    func stopControllers() { launcherControllers?.shutdown(); launcherControllers = nil }
    func controllerMove(_ direction: ControllerNavigation.Direction) {
        switch direction {
        case .down: focusedDock = focusedDock ?? 0
        case .up: focusedDock = nil
        case .left: if let index = focusedDock { focusedDock = max(0, index - 1) } else { move(-1) }
        case .right: if let index = focusedDock { focusedDock = min(5, index + 1) } else { move(1) }
        }
    }
    func controllerConfirm() {
        guard panel == nil else { return }
        if let index = focusedDock {
            let panels: [MacPanel] = [.chat, .store, .controllers, .library, .settings]
            if panels.indices.contains(index) { panel = panels[index] }
            else if index == panels.count { quit() }
        }
        else { launch() }
    }
    func quit() { NSApp.terminate(nil) }
    func controllerBack() { if panel != nil { panel = nil } else { focusedDock = nil } }
    private var process: Process?
    private var logHandle: FileHandle?
    private var stopping = false
    private var libraryWritable = false
    private var refreshTask: Task<Void, Never>?
    private var coverCache = MacCoverCache()
    private var choosingPhoto = false
    let directory = URL.applicationSupportDirectory.appendingPathComponent("com.odestins.switch.mac", isDirectory: true)
    var libraryFile: URL { directory.appendingPathComponent("library.json") }
    var selected: PreparedGame? { games.first { $0.id == selectedID } }
    var running: PreparedGame? { games.first { $0.id == runningID } }

    init() {
        let file = libraryFile, photoURL = directory.appendingPathComponent("profile.jpg")
        Task {
            defer { isLoading = false }
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try MacLibraryStore.loadRecovering(file)
                }.value
                games = loaded.library.games; libraryWritable = true
                selectedID = UserDefaults.standard.string(forKey: "selectedGame") ?? games.first?.id
                if selected == nil { selectedID = games.first?.id }
                if loaded.recovered { message = "Your library was recovered from its backup. Any damaged original file was kept." }
                refresh()
            } catch { message = "The library could not be read. Your files were kept. \(error.localizedDescription)" }
            let image = await Task.detached(priority: .utility) {
                (try? boundedRead(photoURL, maximum: 20 * 1024 * 1024)).flatMap { Self.thumbnailImage($0, size: 512) }
            }.value
            if let image, photo == nil, !choosingPhoto { photo = NSImage(cgImage: image, size: .zero) }
        }
    }

    func refresh() {
        refreshTask?.cancel()
        let snapshot = games
        let ids = Set(snapshot.map(\.id))
        coverCache.retainSources(Dictionary(uniqueKeysWithValues: snapshot.compactMap { game in
            game.manifest.artworkBase64.map { (game.id, $0) }
        }))
        covers = coverCache.images
        problems = problems.filter { ids.contains($0.key) }
        refreshTask = Task {
            let worker = Task.detached(priority: .utility) {
                var problems: [String: String] = [:]
                for game in snapshot {
                    try Task.checkCancellation()
                    if let problem = game.installationProblem() { problems[game.id] = problem }
                }
                return problems
            }
            do {
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                problems = result
            } catch { /* A newer refresh owns the UI. */ }
        }
    }

    /// Called by lazy card/row tasks, which cancel when the view leaves the viewport.
    func loadCover(_ game: PreparedGame) async {
        guard let source = game.manifest.artworkBase64 else { return }
        if coverCache.image(for: game.id, source: source) != nil { return }
        let worker = Task.detached(priority: .utility) { await MacCoverDecoder.shared.decode(source) }
        let image = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, let image,
              games.first(where: { $0.id == game.id })?.manifest.artworkBase64 == source else { return }
        coverCache.insert(image, for: game.id, source: source)
        covers = coverCache.images
    }

    func select(_ game: PreparedGame) {
        focusedDock = nil
        selectedID = game.id; UserDefaults.standard.set(game.id, forKey: "selectedGame")
    }
    func move(_ delta: Int) {
        guard !games.isEmpty else { return }
        let index = games.firstIndex { $0.id == selectedID } ?? 0
        select(games[min(games.count - 1, max(0, index + delta))])
    }

    private func save(_ next: [PreparedGame]) async throws {
        guard libraryWritable else { throw LibraryError.unreadableLibrary }
        let file = libraryFile
        try await Task.detached(priority: .userInitiated) {
            try MacLibraryStore.write(MacLibrary(games: next), to: file)
        }.value
        games = next; refresh()
    }

    private func canEditLibrary() -> Bool {
        guard !isLoading, !isUpdatingLibrary, !isLaunching else {
            message = "Please wait for the current library operation to finish."; return false
        }
        guard libraryWritable else { message = LibraryError.unreadableLibrary.localizedDescription; return false }
        return true
    }

    func importPreparedGame() {
        guard canEditLibrary() else { return }
        let picker = NSOpenPanel()
        picker.title = "Add a prepared Mac game"
        picker.message = "Choose the SwitchMac.switchmac file in a prepared game's build folder. NSP/XCI files need native preparation first."
        picker.allowedContentTypes = [UTType(filenameExtension: "switchmac") ?? .json]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        isUpdatingLibrary = true
        Task {
            defer { isUpdatingLibrary = false }
            do {
                let game = try await Task.detached(priority: .userInitiated) {
                    var game = try JSONDecoder().decode(PreparedGame.self, from: boundedRead(url, maximum: 3 * 1024 * 1024))
                    // Resources follow the chosen package, not a path supplied inside an imported file.
                    game.root = url.deletingLastPathComponent().path
                    game = try game.validated()
                    if let error = game.installationProblem(), game.playable { throw LibraryError.invalid(error) }
                    return game
                }.value
                guard runningID != game.id else { throw LibraryError.invalid("Close this game before replacing its card.") }
                var next = games; next.removeAll { $0.id == game.id }; next.append(game)
                try await save(next); select(game)
            } catch { message = error.localizedDescription }
        }
    }

    func relink(_ game: PreparedGame) {
        guard canEditLibrary() else { return }
        guard runningID != game.id else { message = "Close this game before changing its folder."; return }
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.title = "Locate \(game.manifest.name)'s build folder"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        isUpdatingLibrary = true
        Task {
            defer { isUpdatingLibrary = false }
            do {
                let replacement = try await Task.detached(priority: .userInitiated) {
                    var replacement = game; replacement.root = url.path
                    replacement = try replacement.validated()
                    if let problem = replacement.installationProblem(), replacement.playable { throw LibraryError.invalid(problem) }
                    return replacement
                }.value
                try await save(games.map { $0.id == game.id ? replacement : $0 })
            } catch { message = error.localizedDescription }
        }
    }

    func remove(_ game: PreparedGame) {
        guard canEditLibrary() else { return }
        guard runningID != game.id else { message = "Close this game before removing its card."; return }
        let alert = NSAlert(); alert.messageText = "Remove \(game.manifest.name) from reSwitch?"
        alert.informativeText = "Only the library card is removed. Game files and saves stay in their current folder."
        alert.addButton(withTitle: "Remove Card"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isUpdatingLibrary = true
        Task {
            defer { isUpdatingLibrary = false }
            do {
                try await save(games.filter { $0.id != game.id })
                if selectedID == game.id { selectedID = games.first?.id }
            } catch { message = error.localizedDescription }
        }
    }

    func launch() {
        guard let game = selected, !isLaunching, !isLoading, !isUpdatingLibrary else { return }
        if let process, process.isRunning {
            if runningID == game.id { NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: []) }
            else { message = "\(running?.manifest.name ?? "Another game") is running. Close it before starting a different game." }
            return
        }
        let defaults = UserDefaults.standard
        let hud = defaults.bool(forKey: "performanceHUD"), fullscreen = defaults.bool(forKey: "fullscreen")
        let ownPlayer = defaults.bool(forKey: "keyboardOwnPlayer")
        isLaunching = true
        Task {
            defer { isLaunching = false }
            do {
                // Folder consent or a disconnected drive must not freeze the UI.
                let prepared = try await Task.detached {
                    let plan = try game.launchPlan(hud: hud, fullscreen: fullscreen, keyboardOwnPlayer: ownPlayer)
                    return (plan, try Self.prepareLog(for: game))
                }.value
                try start(game, plan: prepared.0, log: prepared.1)
            } catch { message = error.localizedDescription; refresh() }
        }
    }

    nonisolated private static func prepareLog(for game: PreparedGame) throws -> URL {
            let fm = FileManager.default
            for child in ["save", "temp", "Logs"] {
                try fm.createDirectory(at: try game.contained("MacPlayer/" + child), withIntermediateDirectories: true)
            }
            let logFolder = try game.contained("MacPlayer/Logs")
            let previous = try fm.contentsOfDirectory(at: logFolder, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in previous.dropFirst(9) { try? fm.removeItem(at: old) }
            let log = logFolder.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).log")
            guard fm.createFile(atPath: log.path, contents: nil) else { throw LibraryError.invalid("The game log could not be created.") }
            return log
    }

    private func start(_ game: PreparedGame, plan: LaunchPlan, log: URL) throws {
            let handle = try FileHandle(forWritingTo: log)
            let task = Process(); task.executableURL = plan.executable; task.arguments = plan.arguments
            task.currentDirectoryURL = plan.workingDirectory
            task.environment = plan.cleanEnvironment(inherited: ProcessInfo.processInfo.environment)
            task.standardOutput = handle; task.standardError = handle
            task.standardInput = FileHandle.nullDevice
            task.terminationHandler = { [weak self] finished in
                let status = finished.terminationStatus
                Task { @MainActor in self?.ended(pid: finished.processIdentifier, status: status) }
            }
            process = task; logHandle = handle; latestLog = log; stopping = false
            do { try task.run() } catch { process = nil; logHandle = nil; try? handle.close(); throw error }
            runningID = game.id
    }

    private func ended(pid: Int32, status: Int32) {
        guard process?.processIdentifier == pid else { return }
        let name = running?.manifest.name ?? "The game"
        process = nil; runningID = nil; try? logHandle?.close(); logHandle = nil
        if status != 0 && !stopping { message = "\(name) closed unexpectedly (code \(status)). You can open its latest log from Settings. Your last committed save is kept." }
        stopping = false
    }

    func stop() {
        guard let process, process.isRunning else { return }
        let alert = NSAlert(); alert.messageText = "Close \(running?.manifest.name ?? "the game")?"
        alert.informativeText = "Save in the game first. Progress since the last completed save will be lost."
        alert.addButton(withTitle: "Keep Playing"); alert.addButton(withTitle: "Close Game")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        stopping = true; process.terminate()
    }

    func choosePhoto() {
        guard !choosingPhoto else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.image]; picker.title = "Choose a profile photo"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        choosingPhoto = true
        let directory = directory
        Task {
            defer { choosingPhoto = false }
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    let data = try boundedRead(url, maximum: 20 * 1024 * 1024)
                    let output = NSMutableData()
                    guard let image = Self.thumbnailImage(data, size: 512),
                          let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                        throw LibraryError.invalid("This photo could not be opened. Choose a JPEG, PNG, or HEIC image.")
                    }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                    guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalid("This photo could not be saved.") }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try (output as Data).write(to: directory.appendingPathComponent("profile.jpg"), options: .atomic)
                    return image
                }.value
                photo = NSImage(cgImage: image, size: .zero)
            } catch { message = error.localizedDescription }
        }
    }

    nonisolated static func thumbnailImage(_ data: Data, size: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return image
    }
}

/// The compressed library limit does not bound decoded pixels. Keep only a small
/// working set, and count actual pixel storage rather than JPEG/base64 bytes.
@MainActor
struct MacCoverCache {
    private struct Entry {
        let source: String
        let image: NSImage
        let cost: Int
        var lastAccess: UInt64
    }
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private let maximumBytes: Int
    private let countLimit: Int
    private(set) var residentBytes = 0
    var images: [String: NSImage] { entries.mapValues(\.image) }

    init(maximumBytes: Int = 24 * 1024 * 1024, countLimit: Int = 32) {
        self.maximumBytes = maximumBytes; self.countLimit = countLimit
    }

    mutating func image(for id: String, source: String) -> NSImage? {
        guard entries[id]?.source == source else { return nil }
        clock &+= 1; entries[id]?.lastAccess = clock
        return entries[id]?.image
    }

    mutating func insert(_ pixels: CGImage, for id: String, source: String) {
        remove(id)
        let cost = pixels.bytesPerRow * pixels.height
        guard cost <= maximumBytes, countLimit > 0 else { return }
        while residentBytes + cost > maximumBytes || entries.count >= countLimit {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(oldest)
        }
        clock &+= 1
        entries[id] = Entry(source: source, image: NSImage(cgImage: pixels, size: .zero), cost: cost, lastAccess: clock)
        residentBytes += cost
    }

    mutating func retainSources(_ sources: [String: String]) {
        for id in Array(entries.keys) where entries[id]?.source != sources[id] { remove(id) }
    }

    private mutating func remove(_ id: String) {
        if let removed = entries.removeValue(forKey: id) { residentBytes -= removed.cost }
    }
}

/// Serial decoding bounds transient memory too, including fast library scrolling.
private actor MacCoverDecoder {
    static let shared = MacCoverDecoder()
    func decode(_ source: String) -> CGImage? {
        guard !Task.isCancelled, let data = Data(base64Encoded: source) else { return nil }
        let image = MacModel.thumbnailImage(data, size: 512)
        return Task.isCancelled ? nil : image
    }
}

enum MacPanel: String, Identifiable { case chat = "Chat", controllers = "Controllers", library = "Game Library", settings = "Settings", store = "Store", profile = "Your Profile"; var id: String { rawValue } }
