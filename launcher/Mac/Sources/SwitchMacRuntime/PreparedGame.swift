import Foundation
import iSwitchCore

/// A local installation descriptor, deliberately separate from portable iPhone game cards.
public struct PreparedGame: Codable, Identifiable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var manifest: GameManifest
    public var root: String
    public var modules: String
    public var romfs: String
    public var shaderMap: String
    public var shaderChain: String
    public var playable: Bool
    public var notes: String
    public var id: String { manifest.id }
    public var rootURL: URL { URL(fileURLWithPath: root, isDirectory: true) }
    public var playerDirectory: URL { rootURL.appendingPathComponent("MacPlayer", isDirectory: true) }

    public init(manifest: GameManifest, root: String, modules: String, romfs: String, shaderMap: String,
                shaderChain: String, playable: Bool = true, notes: String = "") {
        self.manifest = manifest; self.root = root; self.modules = modules; self.romfs = romfs
        self.shaderMap = shaderMap; self.shaderChain = shaderChain; self.playable = playable; self.notes = notes
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw LibraryError.invalid("This Mac game package needs a newer version of reSwitch.") }
        var checked = self
        checked.manifest = try manifest.validated()
        guard root.hasPrefix("/"), root.count < 2000, !root.contains("\0"), notes.count <= 2000,
              shaderChain.range(of: "^[a-f0-9]{12}$", options: .regularExpression) != nil else {
            throw LibraryError.invalid("The Mac game configuration is invalid.")
        }
        for path in [modules, romfs, shaderMap] { _ = try contained(path) }
        return checked
    }

    public func contained(_ relative: String) throws -> URL {
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\0"),
              !relative.split(separator: "/").contains("..") else { throw LibraryError.invalid("A game resource path is invalid.") }
        let base = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let result = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard result.path.hasPrefix(base.path + "/") else { throw LibraryError.invalid("A game resource points outside its prepared folder.") }
        return result
    }

    public func installationProblem() -> String? {
        do {
            _ = try validated()
            if !playable { return "Not playable yet" }
            let fm = FileManager.default
            for path in [modules + "/main.fixups.tsv", modules + "/main.patched.bin", romfs, shaderMap, "shader/cache/b-" + shaderChain + "/inputs.tsv"] {
                guard fm.fileExists(atPath: try contained(path).path) else { return "Files missing — relink game folder" }
            }
            let exe = try contained("MacPlayer/Runtime/dmhost")
            guard fm.isExecutableFile(atPath: exe.path) else { return "Mac runtime needs preparation" }
            return nil
        } catch { return error.localizedDescription }
    }

    public func launchPlan(hud: Bool, fullscreen: Bool, keyboardOwnPlayer: Bool) throws -> LaunchPlan {
        if let problem = installationProblem() { throw LibraryError.invalid(problem) }
        // Reading an executable in Documents can trigger macOS's folder consent.
        // Defer this until an explicit launch, never block HOME during startup.
        let executable = try contained("MacPlayer/Runtime/dmhost")
        let handle = try FileHandle(forReadingFrom: executable); defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data([0xcf, 0xfa, 0xed, 0xfe]) else {
            throw LibraryError.invalid("The native Mac runtime is invalid. Prepare this game's Mac package again.")
        }
        return LaunchPlan(executable: try contained("MacPlayer/Runtime/dmhost"),
                          arguments: [try contained(modules).path], workingDirectory: try contained("MacPlayer"),
                          environment: [
                            "DM_ROOT": root, "DM_ROMFS": try contained(romfs).path,
                            "DM_SAVE": try contained("MacPlayer/save").path,
                            "DM_TEMP": try contained("MacPlayer/temp").path,
                            "DM_MSL_DIR": try contained("shader/cache").path,
                            "DM_NVN_SHMAP": try contained(shaderMap).path,
                            "DM_FONT_DIR": try contained("font").path,
                            "DM_WINDOW": "1", "DM_AUDIO": "1", "DM_LANG": "en-US",
                            "DM_METAL_HUD": hud ? "1" : "0", "MTL_HUD_ENABLED": hud ? "1" : "0"
                          ].merging(fullscreen ? ["DM_FULLSCREEN": "1"] : [:]) { _, new in new }
                           .merging(keyboardOwnPlayer ? ["DM_KBD_PLAYER": "own"] : [:]) { _, new in new })
    }
}

public struct LaunchPlan: Sendable {
    public var executable: URL
    public var arguments: [String]
    public var workingDirectory: URL
    public var environment: [String: String]
    public func cleanEnvironment(inherited: [String: String]) -> [String: String] {
        inherited.filter { !$0.key.hasPrefix("DM_") && !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("MTL_") }
            .merging(environment) { _, new in new }
    }
}

public struct MacLibrary: Codable, Sendable {
    public var schemaVersion = 1
    public var games: [PreparedGame] = []
    public init(games: [PreparedGame] = []) { self.games = games }
    public func validated() throws -> Self {
        guard schemaVersion == 1, games.count <= 500 else {
            throw LibraryError.invalid("The Mac library format is invalid. Your game files are safe.")
        }
        let checked = try games.map { try $0.validated() }
        guard Set(checked.map(\.id)).count == checked.count else {
            throw LibraryError.invalid("This Mac library contains the same game more than once.")
        }
        return MacLibrary(games: checked)
    }
}

public enum MacLibraryStore {
    public static let maximumBytes = 32 * 1024 * 1024
    public static func read(_ file: URL) throws -> MacLibrary {
        try decode(boundedRead(file, maximum: maximumBytes))
    }
    private static func decode(_ data: Data) throws -> MacLibrary {
        try JSONDecoder().decode(MacLibrary.self, from: data).validated()
    }
    public static func write(_ library: MacLibrary, to file: URL) throws {
        let checked = try library.validated()
        // Reject oversized output before touching either copy. A library we save
        // must be readable by the next launch, including JSON escaping overhead.
        guard checked.games.reduce(0, { $0 + ($1.manifest.artworkBase64?.utf8.count ?? 0) }) <= maximumBytes else {
            throw LibraryError.invalid("The Mac library is too large (32 MB maximum). Use smaller cover images.")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(checked)
        guard data.count <= maximumBytes else {
            throw LibraryError.invalid("The Mac library is too large (32 MB maximum). Use smaller cover images.")
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Never promote an unreadable primary file over the last known-good backup.
        if let previous = try? boundedRead(file, maximum: maximumBytes), (try? decode(previous)) != nil {
            try previous.write(to: file.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }

    public struct Loaded: Sendable {
        public var library: MacLibrary
        public var recovered: Bool
    }
    /// A missing primary may be an interrupted migration; consult its backup too.
    public static func loadRecovering(_ file: URL) throws -> Loaded {
        let fm = FileManager.default, backup = file.appendingPathExtension("backup")
        let exists = fm.fileExists(atPath: file.path)
        if !exists && !fm.fileExists(atPath: backup.path) {
            return Loaded(library: MacLibrary(), recovered: false)
        }
        if let library = try? read(file) { return Loaded(library: library, recovered: false) }
        let library = try read(backup)
        if exists {
            try fm.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("recovery-\(UUID()).json"))
        }
        try write(library, to: file)
        return Loaded(library: library, recovered: true)
    }
}
