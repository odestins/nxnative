import SwiftUI
import iSwitchCore
import ImageIO
import UniformTypeIdentifiers
import GameController
import Metal

extension UTType {
    static let iswitchGame = UTType(exportedAs: "com.odestins.iswitch.game", conformingTo: .json)
    static let iswitchLibrary = UTType(exportedAs: "com.odestins.iswitch.library", conformingTo: .json)
}

enum Panel: String, Identifiable {
    case add, library, setup, controllers, settings, profile, details, sources, gameChat, store
    var id: String { rawValue }
    var title: String {
        switch self {
        case .add: "Add games"
        case .library: "All software"
        case .setup: "Getting ready"
        case .controllers: "Controllers"
        case .settings: "Settings"
        case .profile: "Your profile"
        case .details: "Game details"
        case .sources: "Games, keys & firmware"
        case .gameChat: "Chat"
        case .store: "Store"
        }
    }
}

struct AppNotice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct CatalogGame: Decodable, Identifiable {
    var titleID: String
    var name: String
    var versions: [String]
    var id: String { titleID }
    var manifest: GameManifest { GameManifest(titleID: titleID, name: name) }
}

/// File coordination, bounded decoding and thumbnail work execute off the UI actor.
actor GameImporter {
    func read(_ url: URL) throws -> (games: [GameManifest], artwork: [String: Data]) {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard ["iswitch", "iswitchlibrary"].contains(url.pathExtension.lowercased()) else {
            throw LibraryError.invalid("Choose an .iswitch game card or .iswitchlibrary backup. Prepare NSP/XCI files on your Mac first.")
        }
        var readResult: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            readResult = Result { try boundedRead(coordinated, maximum: GameTransfer.maximumBytes) }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw LibraryError.invalid("The selected file could not be opened.") }
        let games = try GameTransfer.decode(readResult.get())
        var artwork: [String: Data] = [:]
        for game in games {
            if let encoded = game.artworkBase64, let data = Data(base64Encoded: encoded) {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 8192, height <= 8192,
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { throw LibraryError.invalid("The cover image for \(game.name) could not be read.") }
                let normalized = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(normalized, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw LibraryError.invalid("The cover image could not be saved.")
                }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw LibraryError.invalid("The cover image could not be saved.") }
                artwork[game.id] = normalized as Data
            }
        }
        return (games, artwork)
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var games: [LibraryGame] = []
    @Published var selectedID: String?
    @Published var panel: Panel?
    @Published var notice: AppNotice?
    @Published var isBusy = false
    @Published var importingSource = false
    @Published var loaded = false
    private var loading = false
    @Published var isPreview = false
    @Published var libraryError: String?
    @Published var controllerNames: [String] = []
    @Published var focusedDock: ConsoleAction?
    @Published var exportURL: URL?
    @Published var profilePhoto: UIImage?
    var didOpenGame: ((String) -> Void)?
    let repository: LibraryRepository
    let sourceVault: SourceVault
    let profilePhotoStore: ProfilePhotoStore
    let directory: URL
    let catalog: [CatalogGame]
    private let importer = GameImporter()
    private var controllerObservers: [NSObjectProtocol] = []
    private var controllers: [GCController] = []
    private var controllerTimer: Timer?
    private var controllerNavigation = ControllerNavigation()
    private var controllersActive = false
    private var openingGame = false
    private var importQueue: [URL] = []

    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        directory = URL.applicationSupportDirectory.appendingPathComponent(testing ? "iSwitch-UITests" : "iSwitch", isDirectory: true)
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-test-library") {
            try? FileManager.default.removeItem(at: directory)
        }
        #else
        directory = URL.applicationSupportDirectory.appendingPathComponent("iSwitch", isDirectory: true)
        #endif
        repository = LibraryRepository(directory: directory)
        profilePhotoStore = ProfilePhotoStore(directory: directory)
        sourceVault = SourceVault(directory: directory.appendingPathComponent("Sources", isDirectory: true), testing: directory.lastPathComponent.contains("UITests"))
        if let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([CatalogGame].self, from: data) {
            catalog = entries
        } else { catalog = [] }
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            controllerObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateControllers() }
            })
        }
        updateControllers()
    }

    var visibleGames: [LibraryGame] { isPreview ? Self.previewGames : LibrarySort.recent.sorted(games) }
    var selectedGame: LibraryGame? { visibleGames.first { $0.id == selectedID } ?? visibleGames.first }
    var supportsGameGraphics: Bool { MTLCreateSystemDefaultDevice()?.supportsBCTextureCompression ?? false }
    var artworkDirectory: URL { directory.appendingPathComponent("Artwork", isDirectory: true) }

    func load() async {
        guard !loaded, !loading else { return }
        loading = true
        defer { loading = false }
        if let data = try? await profilePhotoStore.load() { profilePhoto = UIImage(data: data) }
        do {
            let snapshot = try await repository.load()
            games = snapshot.games
            if let message = snapshot.recoveryMessage { notice = AppNotice(title: "Library recovered", message: message) }
        } catch { libraryError = error.localizedDescription }
        loaded = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-library") { isPreview = true }
        #endif
        selectedID = visibleGames.first?.id
    }

    func select(_ id: String) {
        focusedDock = nil
        if selectedID != id { selectedID = id; haptic() }
    }

    func setProfilePhoto(_ file: URL) async throws {
        profilePhoto = UIImage(data: try await profilePhotoStore.save(file))
    }

    func removeProfilePhoto() async {
        do { try await profilePhotoStore.remove(); profilePhoto = nil } catch { show(error) }
    }

    func haptic() {
        if UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true { UISelectionFeedbackGenerator().selectionChanged() }
    }

    func togglePreview() {
        isPreview.toggle(); selectedID = visibleGames.first?.id
    }

    func importFiles(_ urls: [URL]) {
        // Serial queue also covers multiple onOpenURL events from Files/AirDrop.
        guard urls.count + importQueue.count <= 50 else {
            notice = AppNotice(title: "Choose fewer files", message: "Import up to 50 game cards at a time."); return
        }
        importQueue.append(contentsOf: urls)
        guard !isBusy else { return }
        isBusy = true
        Task {
            var imported = 0, errors: [String] = []
            while !importQueue.isEmpty {
                let url = importQueue.removeFirst()
                do {
                    let result = try await importer.read(url)
                    games = try await repository.importGames(result.games, artwork: result.artwork)
                    selectedID = result.games.first?.id
                    imported += result.games.count
                    isPreview = false
                } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            isBusy = false
            notice = AppNotice(title: errors.isEmpty ? "Library updated" : "Import results",
                               message: (imported > 0 ? "Added or updated \(imported) game card\(imported == 1 ? "" : "s"). Install each prepared game app before opening it here." : "")
                                + (errors.isEmpty ? "" : "\n\n" + errors.joined(separator: "\n\n")))
        }
    }

    func add(_ game: CatalogGame) {
        Task {
            do {
                games = try await repository.importGames([game.manifest])
                isPreview = false; selectedID = game.id
                notice = AppNotice(title: "Added to your library", message: "\(game.name) is on your preparation list. Prepare it on your Mac, install the game app, then import its .iswitch card.")
            } catch { show(error) }
        }
    }

    func addManual(titleID: String, name: String, source: SourceReference?) async throws {
        let id = titleID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let manifest = try GameManifest(titleID: id, name: name, compatibility: catalog.contains { $0.id == id } ? .profiled : .experimental).validated()
        games = try await repository.importGames([manifest])
        if let source { try await sourceVault.assign(source, titleID: manifest.id) }
        isPreview = false; selectedID = manifest.id
    }

    func openFile(_ url: URL) {
        guard url.isFileURL else { return }
        if ["iswitch", "iswitchlibrary"].contains(url.pathExtension.lowercased()) { importFiles([url]); return }
        panel = .sources
        pendingSourceURL = url
        NotificationCenter.default.post(name: .importSourceFile, object: url)
    }

    var pendingSourceURL: URL?

    func favorite(_ game: LibraryGame) {
        guard !isPreview else { return }
        Task { do { games = try await repository.toggleFavorite(id: game.id) } catch { show(error) } }
    }

    func remove(_ game: LibraryGame) {
        guard !isPreview else { return }
        Task {
            do {
                games = try await repository.remove(id: game.id)
                if selectedID == game.id { selectedID = visibleGames.first?.id }
                panel = nil
            } catch { show(error) }
        }
    }

    func launch(_ game: LibraryGame, restoreSnapshot: String? = nil) {
        guard !openingGame else { return }
        if isPreview {
            notice = AppNotice(title: "Layout preview", message: "This is an original sample cover, not an installed game. Add your own prepared games to play."); return
        }
        guard game.manifest.buildState != .planned else { panel = .setup; return }
        guard let url = try? game.manifest.launchRequestURL(showPerformanceHUD: UserDefaults.standard.bool(forKey: "performanceHUD"), restoreSnapshot: restoreSnapshot) else {
            notice = AppNotice(title: "Invalid game card", message: "Reimport this game's card from your Mac."); return
        }
        let required = game.manifest.minimumOS.split(separator: ".").map { Int($0) ?? 0 }
        let os = OperatingSystemVersion(majorVersion: required[0], minorVersion: required[1], patchVersion: required.count > 2 ? required[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(os) else {
            notice = AppNotice(title: "iOS update needed", message: "This game requires iOS \(game.manifest.minimumOS) or later."); return
        }
        openingGame = true
        // open() can launch dynamic per-title schemes without the 50-entry canOpenURL allowlist.
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard let self else { return }
            self.openingGame = false
            Task { @MainActor in
                do { self.games = try await self.repository.recordLaunch(id: game.id, opened: success) }
                catch { self.show(error) }
                if success { self.didOpenGame?(game.manifest.name) }
                if !success {
                    self.notice = AppNotice(title: "Game app not available", message: "Install \(game.manifest.name) using the Xcode project or signed IPA prepared with this fork. If it is already installed, rebuild it with launcher support. The library card alone does not contain the game.")
                }
            }
        }
    }

    func exportLibrary() async {
        exportURL = nil
        do {
            let data = try await repository.exportLibrary()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("reSwitch Library.iswitchlibrary")
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch { show(error) }
    }

    func show(_ error: Error) { notice = AppNotice(title: "Couldn’t complete that", message: error.localizedDescription) }

    func resetLibrary() async {
        do {
            games = try await repository.resetPreservingRecoveryFiles()
            libraryError = nil; selectedID = nil; isPreview = false
        } catch { show(error) }
    }

    func updateControllers() {
        controllerTimer?.invalidate(); controllerTimer = nil
        controllerNavigation.reset()
        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }
            pad.dpad.valueChangedHandler = nil
            pad.leftThumbstick.valueChangedHandler = nil
            pad.buttonA.pressedChangedHandler = nil
            pad.buttonB.pressedChangedHandler = nil
            pad.buttonY.pressedChangedHandler = nil
            pad.buttonMenu.pressedChangedHandler = nil
        }
        controllers = GCController.controllers().filter { $0.extendedGamepad != nil }
        controllerNames = controllers.map { $0.vendorName ?? "Game controller" }
        if controllers.isEmpty { focusedDock = nil }
        guard controllersActive else { return }
        for controller in controllers {
            controller.handlerQueue = .main
            guard let pad = controller.extendedGamepad else { continue }
            pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in
                    guard let self, self.acceptsControllerInput, self.panel == nil else { return }
                    if let action = self.focusedDock { self.activateConsoleAction(action) }
                    else if let game = self.selectedGame { self.launch(game) }
                    else { self.panel = .add }
                }
            }
            pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in
                    guard let self, self.acceptsControllerInput else { return }
                    if self.panel != nil { self.panel = nil } else { self.focusedDock = nil }
                }
            }
            pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in
                    guard let self, self.acceptsControllerInput, self.panel == nil else { return }
                    self.panel = .library
                }
            }
            pad.buttonMenu.pressedChangedHandler = pad.buttonY.pressedChangedHandler
        }
        guard !controllers.isEmpty else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollControllerNavigation() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        controllerTimer = timer
    }

    func setControllersActive(_ active: Bool) {
        guard controllersActive != active else { return }
        controllersActive = active
        updateControllers()
    }

    private var acceptsControllerInput: Bool {
        controllersActive && UIApplication.shared.applicationState == .active
            && notice == nil && !openingGame && !importingSource
    }

    private func pollControllerNavigation() {
        guard acceptsControllerInput, panel == nil else { controllerNavigation.reset(); return }
        var x: Float = 0, y: Float = 0
        for controller in controllers {
            guard let pad = controller.extendedGamepad else { continue }
            for input in [pad.dpad, pad.leftThumbstick] {
                let ix = input.xAxis.value, iy = input.yAxis.value
                if max(abs(ix), abs(iy)) > max(abs(x), abs(y)) { x = ix; y = iy }
            }
        }
        if let direction = controllerNavigation.update(x: x, y: y, now: ProcessInfo.processInfo.systemUptime) {
            moveController(direction)
        }
    }

    func moveController(_ direction: ControllerNavigation.Direction) {
        guard panel == nil, notice == nil else { return }
        switch direction {
        case .down: if focusedDock == nil { focusedDock = .chat; haptic() }
        case .up: if focusedDock != nil { focusedDock = nil; haptic() }
        case .left, .right:
            let step = direction == .left ? -1 : 1
            if let action = focusedDock, let index = ConsoleAction.allCases.firstIndex(of: action) {
                let next = min(max(index + step, 0), ConsoleAction.allCases.count - 1)
                if next != index { focusedDock = ConsoleAction.allCases[next]; haptic() }
            } else {
                let games = visibleGames
                guard let current = selectedGame, let index = games.firstIndex(where: { $0.id == current.id }) else { return }
                select(games[min(max(index + step, 0), games.count - 1)].id)
            }
        }
    }

    func activateConsoleAction(_ action: ConsoleAction) {
        haptic()
        switch action {
        case .chat: panel = .gameChat
        case .shop: panel = .store
        case .controllers: panel = .controllers
        case .cards: panel = .sources
        case .settings: panel = .settings
        }
    }

    static let previewGames: [LibraryGame] = [
        ("F000000000000001", "AETHER", "Skybound adventures"),
        ("F000000000000002", "ORBIT RALLY", "Beyond the finish line"),
        ("F000000000000003", "EVERGREEN", "A little room to grow"),
        ("F000000000000004", "NEON DRIFT", "After hours"),
        ("F000000000000005", "TIDELANDS", "Find your horizon")
    ].map { LibraryGame(manifest: GameManifest(titleID: $0.0, name: $0.1, version: $0.2, buildState: .packaged)) }
}
