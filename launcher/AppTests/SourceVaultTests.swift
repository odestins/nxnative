import XCTest
@testable import iSwitch

final class SourceVaultTests: XCTestCase, @unchecked Sendable {
    private var root: URL!
    private var vault: SourceVault!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vault-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = SourceVault(directory: root.appendingPathComponent("Store"), testing: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testImportOwnsAnOfflineCopyAndRemovalLeavesOriginalAlone() async throws {
        let source = root.appendingPathComponent("Synthetic [0100000000000000].nsp")
        let data = Data("PFS0".utf8) + Data(repeating: 0, count: 4096)
        try data.write(to: source)
        let reference = try await vault.add(source, kind: .game)
        let local = root.appendingPathComponent("Store").appendingPathComponent(reference.localFilename)
        XCTAssertEqual(try Data(contentsOf: local), data)
        try Data("replaced original".utf8).write(to: source)
        XCTAssertEqual(try Data(contentsOf: local), data)
        let reloaded = SourceVault(directory: root.appendingPathComponent("Store"), testing: true)
        let before = try await reloaded.snapshot()
        XCTAssertEqual(before.files.count, 1)
        try await reloaded.remove(id: reference.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("replaced original".utf8))
    }

    func testInvalidFilesDoNotEnterIndexAndInterruptedCopiesAreCleaned() async throws {
        let bad = root.appendingPathComponent("Renamed installer.nsp")
        try Data("MZ installer".utf8).write(to: bad)
        do { _ = try await vault.add(bad, kind: .game); XCTFail("Must reject renamed installer") } catch {}
        let partial = root.appendingPathComponent("Store/unfinished.nsp.partial")
        try Data([0]).write(to: partial)
        let result = try await vault.snapshot()
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }

    func testKeychainReplacementRejectsInvalidInputWithoutLosingExistingKeys() async throws {
        try await vault.removeKeys()
        let source = root.appendingPathComponent("prod.keys")
        let fixture = Data(("header_key = " + String(repeating: "ab", count: 32) + "\n").utf8)
        try fixture.write(to: source)
        let count = try await vault.importKeys(source)
        XCTAssertEqual(count, 1)
        try Data("invalid".utf8).write(to: source)
        do { _ = try await vault.importKeys(source); XCTFail("Must reject invalid key replacement") } catch {}
        let result = try await vault.snapshot()
        XCTAssertNil(result.keyError)
        XCTAssertEqual(result.keyCount, 1)
        try await vault.removeKeys()
        let removed = try await vault.snapshot()
        XCTAssertNil(removed.keyCount)
    }

    func testInterruptedDeletionRestoresIndexedDataAndCleansCommittedRemoval() async throws {
        let source = root.appendingPathComponent("Synthetic.nsp")
        try (Data("PFS0".utf8) + Data(repeating: 0, count: 4096)).write(to: source)
        let reference = try await vault.add(source, kind: .game)
        let local = root.appendingPathComponent("Store").appendingPathComponent(reference.localFilename)
        let deleting = local.appendingPathExtension("deleting")
        try FileManager.default.moveItem(at: local, to: deleting)
        let restarted = SourceVault(directory: root.appendingPathComponent("Store"), testing: true)
        try await restarted.assign(reference, titleID: "0100000000000000")
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path), "A mutation before the first snapshot must recover the indexed copy")
        let restored = try await restarted.snapshot()
        XCTAssertEqual(restored.files.count, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
        try FileManager.default.moveItem(at: local, to: deleting)
        try Data("[]".utf8).write(to: root.appendingPathComponent("Store/references.json"), options: .atomic)
        let afterCommit = SourceVault(directory: root.appendingPathComponent("Store"), testing: true)
        try await afterCommit.remove(id: reference.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleting.path), "Retrying the committed deletion must release its imported copy")
        let removed = try await afterCommit.snapshot()
        XCTAssertTrue(removed.files.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: deleting.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDeletionRecoveryPreservesConflictingCopiesAndIndex() async throws {
        let source = root.appendingPathComponent("Synthetic.nsp")
        let payload = Data("PFS0".utf8) + Data(repeating: 0, count: 4096)
        try payload.write(to: source)
        let reference = try await vault.add(source, kind: .game)
        let local = root.appendingPathComponent("Store").appendingPathComponent(reference.localFilename)
        let deleting = local.appendingPathExtension("deleting")
        try FileManager.default.copyItem(at: local, to: deleting)
        let other = Data("conflicting copy".utf8)
        try other.write(to: local)
        let snapshot = try await vault.snapshot()
        XCTAssertEqual(snapshot.files.map(\.id), [reference.id])
        do { try await vault.remove(id: reference.id); XCTFail("Conflicting recovery files must not be discarded") } catch {}
        XCTAssertEqual(try Data(contentsOf: deleting), payload)
        XCTAssertEqual(try Data(contentsOf: local), other)
        let retained = try await vault.snapshot()
        XCTAssertEqual(retained.files.map(\.id), [reference.id])
        try FileManager.default.removeItem(at: local)
        try other.write(to: deleting)
        let incomplete = try await vault.snapshot()
        XCTAssertEqual(incomplete.missingFileIDs, [reference.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path), "An incomplete deletion copy must not be restored as a complete import")
        XCTAssertEqual(try Data(contentsOf: deleting), other)
    }

    func testDeletionRecoveryIgnoresUnownedFilesLinksAndDirectories() async throws {
        let store = root.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: store.appendingPathComponent("references.json"))
        let unrelated = store.appendingPathComponent("personal.nsp.deleting")
        let unjournaled = store.appendingPathComponent(UUID().uuidString + ".nsp")
        let outside = root.appendingPathComponent("outside.nsp")
        for url in [unrelated, unjournaled, outside] { try Data([1, 2, 3]).write(to: url) }
        let link = store.appendingPathComponent(UUID().uuidString + ".nsp.deleting")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let folder = store.appendingPathComponent(UUID().uuidString + ".zip.deleting")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let dangling = store.appendingPathComponent(UUID().uuidString + ".nsp")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("missing"))
        let conflict = dangling.appendingPathExtension("deleting")
        try Data([4]).write(to: conflict)
        _ = try await vault.snapshot()
        for url in [unrelated, unjournaled, outside, link, folder, conflict] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
        XCTAssertNoThrow(try FileManager.default.destinationOfSymbolicLink(atPath: dangling.path))
    }

    func testDeletionRecoveryNeedsAValidIndexBeforeDiscardingData() async throws {
        let store = root.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let deleting = store.appendingPathComponent(UUID().uuidString + ".nsp.deleting")
        let payload = Data("recoverable copy".utf8)
        try payload.write(to: deleting)
        do { _ = try await vault.snapshot(); XCTFail("A missing index is not evidence of a committed removal") } catch {}
        XCTAssertEqual(try Data(contentsOf: deleting), payload)
        let index = store.appendingPathComponent("references.json")
        try Data("damaged index".utf8).write(to: index)
        do { _ = try await vault.snapshot(); XCTFail("A damaged index is not evidence of a committed removal") } catch {}
        XCTAssertEqual(try Data(contentsOf: deleting), payload)
        XCTAssertEqual(try Data(contentsOf: index), Data("damaged index".utf8))
    }

    func testInterruptedImportRecoversCompleteCopyAndMetadata() async throws {
        let source = root.appendingPathComponent("Recovered [0100000000000000].nsp")
        try (Data("PFS0".utf8) + Data(repeating: 0, count: 4096)).write(to: source)
        let reference = try await vault.add(source, kind: .game)
        let store = root.appendingPathComponent("Store")
        let journal = store.appendingPathComponent(reference.localFilename + ".importing")
        try JSONEncoder().encode(reference).write(to: journal)
        try Data("[]".utf8).write(to: store.appendingPathComponent("references.json"), options: .atomic)
        let restored = try await vault.snapshot()
        XCTAssertEqual(restored.files.map(\.id), [reference.id])
        XCTAssertEqual(restored.files.first?.filename, source.lastPathComponent)
        XCTAssertEqual(restored.files.first?.titleID, reference.titleID)
        XCTAssertTrue(restored.missingFileIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        let restarted = try await SourceVault(directory: store, testing: true).snapshot()
        XCTAssertEqual(restarted.files.map(\.id), [reference.id])
    }

    func testInterruptedImportBeforeFileCommitDoesNotCreateUnavailableEntry() async throws {
        let store = root.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let reference = SourceReference(kind: .game, filename: "Not copied.nsp", bytes: 4096, localFilename: UUID().uuidString + ".nsp")
        let journal = store.appendingPathComponent(reference.localFilename + ".importing")
        let partial = store.appendingPathComponent(reference.localFilename + ".partial")
        try JSONEncoder().encode(reference).write(to: journal)
        try Data([1]).write(to: partial)
        let snapshot = try await vault.snapshot()
        XCTAssertTrue(snapshot.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testMissingAndTruncatedCopiesAreReportedWithoutLosingIndex() async throws {
        let source = root.appendingPathComponent("Synthetic.nsp")
        try (Data("PFS0".utf8) + Data(repeating: 0, count: 4096)).write(to: source)
        let reference = try await vault.add(source, kind: .game)
        let local = root.appendingPathComponent("Store").appendingPathComponent(reference.localFilename)
        try Data([0]).write(to: local)
        let truncated = try await vault.snapshot()
        XCTAssertEqual(truncated.files.count, 1)
        XCTAssertEqual(truncated.missingFileIDs, [reference.id])
        try FileManager.default.removeItem(at: local)
        let missing = try await vault.snapshot()
        XCTAssertEqual(missing.files.count, 1)
        XCTAssertEqual(missing.missingFileIDs, [reference.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testInvalidRecoveryJournalNeverEscapesVaultOrRewritesIndex() async throws {
        let store = root.appendingPathComponent("Store")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let index = store.appendingPathComponent("references.json")
        try Data("[]".utf8).write(to: index)
        let reference = SourceReference(kind: .game, filename: "Unsafe.nsp", bytes: 1, localFilename: "../outside.nsp")
        let journal = store.appendingPathComponent("unsafe.importing")
        try JSONEncoder().encode(reference).write(to: journal)
        do { _ = try await vault.snapshot(); XCTFail("Must reject unsafe recovery paths") } catch {}
        XCTAssertEqual(try Data(contentsOf: index), Data("[]".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }
}
