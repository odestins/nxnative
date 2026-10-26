import XCTest
import SwitchMacRuntime
import iSwitchCore

final class RuntimeTests: XCTestCase {
    func fixture() throws -> PreparedGame {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let game = PreparedGame(manifest: GameManifest(titleID: "010015100B514000", name: "Test"), root: root.path,
                                modules: "patched_v1", romfs: "extract/v1/RomFS", shaderMap: "profile/shader_map.tsv", shaderChain: "657c42552d82")
        for relative in ["patched_v1/main.fixups.tsv", "patched_v1/main.patched.bin", "extract/v1/RomFS/marker", "profile/shader_map.tsv", "shader/cache/b-657c42552d82/inputs.tsv", "MacPlayer/Runtime/dmhost"] {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("MacPlayer/Runtime/dmhost").path)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return game
    }
    func testLaunchIsolationAndSettings() throws {
        let game = try fixture()
        let plan = try game.launchPlan(hud: true, fullscreen: false, keyboardOwnPlayer: true)
        XCTAssertEqual(plan.arguments, [game.root + "/patched_v1"])
        XCTAssertEqual(plan.environment["DM_SAVE"], game.root + "/MacPlayer/save")
        let env = plan.cleanEnvironment(inherited: ["DM_KEYS": "1:A", "DM_FULLSCREEN": "1", "DYLD_INSERT_LIBRARIES": "/bad", "PATH": "/usr/bin", "MTL_CAPTURE_ENABLED": "1"])
        XCTAssertNil(env["DM_KEYS"]); XCTAssertNil(env["DM_FULLSCREEN"]); XCTAssertNil(env["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(env["MTL_CAPTURE_ENABLED"]); XCTAssertEqual(env["PATH"], "/usr/bin")
        XCTAssertEqual(env["DM_METAL_HUD"], "1"); XCTAssertEqual(env["DM_KBD_PLAYER"], "own")
    }
    func testBlockedAndMissingGamesNeverLaunch() throws {
        var game = try fixture(); game.playable = false
        XCTAssertThrowsError(try game.launchPlan(hud: false, fullscreen: false, keyboardOwnPlayer: false))
        game.playable = true
        try FileManager.default.removeItem(at: game.rootURL.appendingPathComponent("patched_v1/main.fixups.tsv"))
        XCTAssertThrowsError(try game.launchPlan(hud: false, fullscreen: false, keyboardOwnPlayer: false))
    }
    func testTraversalAndSymlinkEscapeRejected() throws {
        var game = try fixture(); game.modules = "../outside"
        XCTAssertThrowsError(try game.validated())
        game.modules = "outside"
        try FileManager.default.createSymbolicLink(atPath: game.root + "/outside", withDestinationPath: "/tmp")
        XCTAssertThrowsError(try game.validated())
        XCTAssertThrowsError(try game.contained("/bin/sh"))
    }
    func testNonNativeExecutableRejectedAtLaunch() throws {
        let game = try fixture()
        try Data("#!/bin/sh\necho wrong\n".utf8).write(to: game.rootURL.appendingPathComponent("MacPlayer/Runtime/dmhost"))
        XCTAssertThrowsError(try game.launchPlan(hud: false, fullscreen: false, keyboardOwnPlayer: false))
    }
    func testLibraryBackupSurvivesUnreadablePrimary() throws {
        let game = try fixture(), file = game.rootURL.appendingPathComponent("library.json")
        let first = MacLibrary(games: [game]); try MacLibraryStore.write(first, to: file)
        try MacLibraryStore.write(MacLibrary(), to: file)
        XCTAssertEqual(try MacLibraryStore.read(file.appendingPathExtension("backup")).games.count, 1)
        try Data("bad json".utf8).write(to: file)
        XCTAssertThrowsError(try MacLibraryStore.read(file))
        try MacLibraryStore.write(first, to: file)
        XCTAssertEqual(try MacLibraryStore.read(file.appendingPathExtension("backup")).games.count, 1)
        XCTAssertThrowsError(try MacLibrary(games: [game, game]).validated())
    }
    func testOversizedWritePreservesBothCopies() throws {
        let game = try fixture(), file = game.rootURL.appendingPathComponent("library.json")
        try MacLibraryStore.write(MacLibrary(games: [game]), to: file)
        try MacLibraryStore.write(MacLibrary(), to: file)
        let primary = try Data(contentsOf: file), backup = try Data(contentsOf: file.appendingPathExtension("backup"))
        let artwork = Data(repeating: 0xff, count: 1_900_000).base64EncodedString()
        let large = (0..<14).map { index -> PreparedGame in
            var item = game
            item.manifest = GameManifest(titleID: String(format: "%016X", index), name: "Large \(index)", artworkBase64: artwork)
            return item
        }
        XCTAssertThrowsError(try MacLibraryStore.write(MacLibrary(games: large), to: file))
        XCTAssertEqual(try Data(contentsOf: file), primary)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("backup")), backup)
    }
    func testRecoveryWhenPrimaryIsMissing() throws {
        let game = try fixture(), file = game.rootURL.appendingPathComponent("library.json")
        try MacLibraryStore.write(MacLibrary(games: [game]), to: file)
        try MacLibraryStore.write(MacLibrary(), to: file)
        try FileManager.default.removeItem(at: file)
        let loaded = try MacLibraryStore.loadRecovering(file)
        XCTAssertTrue(loaded.recovered)
        XCTAssertEqual(loaded.library.games, [game])
        XCTAssertEqual(try MacLibraryStore.read(file).games, [game])
    }
    func testIdentifiersNormalizeBeforeCheckingDuplicates() throws {
        let game = try fixture()
        var lower = game; lower.manifest.titleID = game.id.lowercased()
        XCTAssertEqual(try lower.validated().id, game.id)
        XCTAssertThrowsError(try MacLibrary(games: [game, lower]).validated())
    }
}
