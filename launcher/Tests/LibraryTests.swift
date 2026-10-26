import XCTest
@testable import iSwitchCore

final class LibraryTests: XCTestCase, @unchecked Sendable {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func card(_ id: String = "010015100B514000", name: String = "Sample game") -> GameManifest {
        GameManifest(titleID: id, name: name, version: "1.2.1", buildState: .packaged)
    }
    private func data(_ card: GameManifest) throws -> Data { try JSONEncoder().encode(card) }

    func testCardAndBatchRoundTrip() throws {
        XCTAssertEqual(try GameTransfer.decode(data(card())), [card()])
        let games = [card(), card("0100000000000000", name: "Second game")]
        XCTAssertEqual(try GameTransfer.decode(JSONEncoder().encode(GameTransfer(games: games))), games)
    }

    func testHUDLaunchRequestKeepsImportedURLsRestricted() throws {
        XCTAssertEqual(try card().launchRequestURL(showPerformanceHUD: true).absoluteString, "nxnative-010015100b514000://launch?hud=1")
        XCTAssertEqual(try card().launchRequestURL(showPerformanceHUD: false).absoluteString, "nxnative-010015100b514000://launch?hud=0")
        var bad = card(); bad.launchURL += "?hud=1"
        XCTAssertThrowsError(try bad.launchRequestURL(showPerformanceHUD: false))
        bad = card(); bad.launchURL = "nxnative-0100000000000000://launch"
        XCTAssertThrowsError(try bad.launchRequestURL(showPerformanceHUD: true))
    }

    func testRejectsHostileURLsAndInvalidMetadata() throws {
        for bad in ["https://example.com", "file:///etc/passwd", "nxnative-010015100b514000://launch?command=x", "nxnative-0100000000000000://launch"] {
            var manifest = card(); manifest.launchURL = bad
            XCTAssertThrowsError(try GameTransfer.decode(data(manifest)))
        }
        var manifest = card(); manifest.titleID = "../library.json"
        XCTAssertThrowsError(try manifest.validated())
        manifest = card(); manifest.schemaVersion = 2
        XCTAssertThrowsError(try manifest.validated())
        manifest = card(); manifest.name = "\n"
        XCTAssertThrowsError(try manifest.validated())
        manifest = card(); manifest.artworkBase64 = "not base64!"
        XCTAssertThrowsError(try manifest.validated())
        manifest = card(); manifest.minimumOS = "tomorrow"
        XCTAssertThrowsError(try manifest.validated())
    }

    func testRejectsOversizedAndDuplicateImports() throws {
        XCTAssertThrowsError(try GameTransfer.decode(Data(repeating: 65, count: GameTransfer.maximumBytes + 1)))
        XCTAssertThrowsError(try GameTransfer.decode(JSONEncoder().encode(GameTransfer(games: [card(), card()]))))
        XCTAssertThrowsError(try GameTransfer.decode(Data("not a game".utf8)))
        let url = root.appendingPathComponent("large.iswitch")
        try Data(repeating: 0, count: 1001).write(to: url)
        XCTAssertThrowsError(try boundedRead(url, maximum: 1000))
    }

    func testDuplicateUpdatePreservesUserStateAndPersists() async throws {
        let repository = LibraryRepository(directory: root)
        _ = try await repository.importGames([card()])
        _ = try await repository.toggleFavorite(id: card().id)
        let when = Date(timeIntervalSince1970: 100)
        _ = try await repository.recordLaunch(id: card().id, opened: true, now: when)
        var update = card(); update.version = "2.0"
        let games = try await repository.importGames([update])
        XCTAssertEqual(games.count, 1)
        XCTAssertTrue(games[0].isFavorite)
        XCTAssertEqual(games[0].lastOpenedAt, when)
        XCTAssertEqual(games[0].lastLaunchResult, .unknown)
        let loaded = try await LibraryRepository(directory: root).load()
        XCTAssertEqual(loaded.games, games)
        _ = try await repository.importGames([GameManifest(titleID: card().id, name: "Planning copy")])
        let retained = try await repository.load()
        XCTAssertEqual(retained.games[0].manifest.version, "2.0")
    }

    func testFailedLaunchDoesNotRecordPlay() async throws {
        let repository = LibraryRepository(directory: root)
        _ = try await repository.importGames([card()])
        let games = try await repository.recordLaunch(id: card().id, opened: false)
        XCTAssertNil(games[0].lastOpenedAt)
        XCTAssertEqual(games[0].status, "Install game app")
    }

    func testCorruptPrimaryRecoversPreviousCopyAndPreservesOriginal() async throws {
        let repository = LibraryRepository(directory: root)
        _ = try await repository.importGames([card()])
        _ = try await repository.toggleFavorite(id: card().id)
        try Data("broken".utf8).write(to: root.appendingPathComponent("library.json"))
        let recovered = try await LibraryRepository(directory: root).load()
        XCTAssertEqual(recovered.games.count, 1)
        XCTAssertFalse(recovered.games[0].isFavorite)
        XCTAssertNotNil(recovered.recoveryMessage)
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("library.recovery-") }.count, 1)
    }

    func testCorruptLibraryNeverSilentlyOverwritesUserData() async throws {
        let original = Data("broken".utf8)
        let url = root.appendingPathComponent("library.json")
        try original.write(to: url)
        let repository = LibraryRepository(directory: root)
        do { _ = try await repository.importGames([card()]); XCTFail("Expected recovery error") }
        catch { XCTAssertEqual(error as? LibraryError, .unreadableLibrary) }
        XCTAssertEqual(try Data(contentsOf: url), original)
        let reset = try await repository.resetPreservingRecoveryFiles()
        XCTAssertTrue(reset.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("library.recovery-") })
    }

    func testFailedWriteDoesNotChangeInMemoryLibrary() async throws {
        let repository = LibraryRepository(directory: root)
        _ = try await repository.importGames([card()])
        let primary = root.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: primary)
        try FileManager.default.createDirectory(at: primary, withIntermediateDirectories: false)
        do { _ = try await repository.toggleFavorite(id: card().id); XCTFail("Write should fail") } catch {}
        let snapshot = try await repository.load()
        XCTAssertFalse(snapshot.games[0].isFavorite)
    }

    func testBatchIsAtomicAndCoversLiveOutsideMetadata() async throws {
        let repository = LibraryRepository(directory: root)
        var invalid = card("0100000000000000"); invalid.name = ""
        do { _ = try await repository.importGames([card(), invalid]); XCTFail("Invalid batch") } catch {}
        let empty = try await repository.load()
        XCTAssertTrue(empty.games.isEmpty)
        var manifest = card(); manifest.artworkBase64 = Data([1, 2]).base64EncodedString()
        let games = try await repository.importGames([manifest], artwork: [manifest.id: Data([1, 2])])
        XCTAssertNil(games[0].manifest.artworkBase64)
        XCTAssertNotNil(games[0].artworkFilename)
        let exported = try await repository.exportLibrary()
        XCTAssertEqual(try GameTransfer.decode(exported)[0].artworkBase64, manifest.artworkBase64)
        _ = try await repository.remove(id: manifest.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Artwork").appendingPathComponent(games[0].artworkFilename!).path))
    }

    func testSearchAndSortUseRealLaunchHistory() {
        var alpha = LibraryGame(manifest: card(name: "Alpha"))
        let beta = LibraryGame(manifest: card("0100000000000000", name: "Beta"))
        alpha.lastOpenedAt = .now; alpha.isFavorite = true
        XCTAssertEqual(LibrarySort.recent.sorted([beta, alpha]).map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(LibrarySort.name.sorted([alpha, beta], search: "BE").map(\.id), [beta.id])
        XCTAssertEqual(LibrarySort.name.sorted([alpha, beta], favoritesOnly: true).map(\.id), [alpha.id])
    }

    func testExportStopsAtSizeBudgetBeforeLoadingFurtherCovers() async throws {
        let repository = LibraryRepository(directory: root)
        let cards = (0..<51).map { card(String(format: "%016llX", UInt64($0))) }
        let cover = Data(repeating: 42, count: 512 * 1024)
        var artwork = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, cover) })
        artwork[cards.last!.id] = Data([1])
        let games = try await repository.importGames(cards, artwork: artwork)
        let lastCover = root.appendingPathComponent("Artwork").appendingPathComponent(try XCTUnwrap(games.last?.artworkFilename))
        try FileManager.default.removeItem(at: lastCover)
        do {
            _ = try await repository.exportLibrary()
            XCTFail("The export must stay within its memory and output budget")
        } catch LibraryError.invalid(let message) {
            XCTAssertTrue(message.contains("too large to export"), message)
        }
        let retained = try await repository.load()
        XCTAssertEqual(retained.games.count, cards.count)
    }

    func testBoundedReadHandlesExactLimitEmptyFilesAndInvalidLimits() throws {
        let url = root.appendingPathComponent("fixture")
        try Data(repeating: 7, count: 128 * 1024).write(to: url)
        XCTAssertEqual(try boundedRead(url, maximum: 128 * 1024).count, 128 * 1024)
        XCTAssertThrowsError(try boundedRead(url, maximum: 128 * 1024 - 1))
        XCTAssertThrowsError(try boundedRead(url, maximum: -1))
        XCTAssertThrowsError(try boundedRead(url, maximum: Int.max))
        XCTAssertThrowsError(try boundedRead(root, maximum: 1024))
        try Data().write(to: url)
        XCTAssertEqual(try boundedRead(url, maximum: 0), Data())
    }
}
