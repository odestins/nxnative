import XCTest
import Darwin
@testable import SwitchSaveSync

final class SaveArchiveTests: XCTestCase {
    let title = "0100AC601DCA8000"
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func manifest() -> SaveManifest {
        let device = UUID().uuidString.lowercased()
        return SaveManifest(titleID: title, game: "Fixture", version: "1", device: device, deviceName: "Test device", clock: SaveClock([device: 1]))
    }
    func testRoundTripIncludesNestedFilesAndEmptyDirectories() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save.appendingPathComponent("slot/empty"), withIntermediateDirectories: true)
        let payload = Data((0..<190000).map { UInt8($0 % 251) })
        try payload.write(to: save.appendingPathComponent("slot/progress.dat"))
        let archive = root.appendingPathComponent("game.switchsave")
        let written = try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        let output = root.appendingPathComponent("restored")
        XCTAssertEqual(try SaveArchive.extract(archive, to: output, expectedTitle: title), written)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("slot/progress.dat")), payload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("slot/empty").path))
    }
    func testCorruptArchiveCannotReplaceExistingSave() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        let original = Data("valuable progress".utf8); try original.write(to: save.appendingPathComponent("progress"))
        let archive = root.appendingPathComponent("bad.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        var bytes = try Data(contentsOf: archive); bytes[bytes.count - 1] ^= 1; try bytes.write(to: archive)
        XCTAssertThrowsError(try SaveArchive.restore(archive, save: save, backups: root.appendingPathComponent("backups"), titleID: title))
        XCTAssertEqual(try Data(contentsOf: save.appendingPathComponent("progress")), original)
    }
    func testRestoreKeepsPreviousSave() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("cloud version".utf8).write(to: save.appendingPathComponent("progress"))
        let archive = root.appendingPathComponent("game.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        try Data("local version".utf8).write(to: save.appendingPathComponent("progress"))
        let backups = root.appendingPathComponent("backups")
        _ = try SaveArchive.restore(archive, save: save, backups: backups, titleID: title)
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("progress")), "cloud version")
        let old = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("progress")), "local version")
    }
    func testRejectsSymlinksAndWrongGame() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: save.appendingPathComponent("link"), withDestinationURL: root)
        XCTAssertThrowsError(try SaveArchive.entries(at: save))
        try FileManager.default.removeItem(at: save.appendingPathComponent("link"))
        try Data("save".utf8).write(to: save.appendingPathComponent("file"))
        let archive = root.appendingPathComponent("game.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        XCTAssertThrowsError(try SaveArchive.extract(archive, to: root.appendingPathComponent("out"), expectedTitle: "0100000000000000"))
    }
    func testRejectsPathTraversalBeforeCreatingOutput() throws {
        let root = try folder(); var m = manifest()
        m.entries = [SaveEntry(path: "../outside", bytes: 0, digest: String(repeating: "0", count: 64), directory: false)]
        m.contentHash = try SaveArchive.fingerprint(m.entries)
        let header = try JSONEncoder().encode(m); var size = UInt32(header.count).littleEndian
        var data = Data("SWITCHSAVE01\n".utf8); withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }; data.append(header)
        let archive = root.appendingPathComponent("bad.switchsave"); try data.write(to: archive)
        XCTAssertThrowsError(try SaveArchive.extract(archive, to: root.appendingPathComponent("out"), expectedTitle: title))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
    }
    func testVectorClocksPreserveConcurrentProgress() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        let left = SaveClock([a: 2]), right = SaveClock([a: 1, b: 1])
        XCTAssertFalse(left.dominates(right)); XCTAssertFalse(right.dominates(left))
        var merged = left.merged(right); try merged.advance(device: a)
        XCTAssertTrue(merged.dominates(left)); XCTAssertTrue(merged.dominates(right))
        var one = manifest(), two = manifest(), three = manifest()
        one.clock = left; two.clock = right; three.clock = merged
        XCTAssertEqual(SaveManifest.heads([one, two]).count, 2)
        XCTAssertEqual(SaveManifest.heads([one, two, three]).map(\.id), [three.id])
    }

    func testGuestFilenameMetadataRoundTrips() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        let file = save.appendingPathComponent(".dm-case-2")
        try Data("case-sensitive save".utf8).write(to: file)
        let metadata = Data("SlotA".utf8)
        XCTAssertEqual(metadata.withUnsafeBytes { setxattr(file.path, "org.d2rmobile.guest-name", $0.baseAddress, metadata.count, 0, XATTR_NOFOLLOW) }, 0)
        let archive = root.appendingPathComponent("save.switchsave"), output = root.appendingPathComponent("output")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        _ = try SaveArchive.extract(archive, to: output, expectedTitle: title)
        XCTAssertEqual(try SaveArchive.entries(at: output).first?.guestName, metadata)
        let unsafe = Data("../outside".utf8)
        XCTAssertEqual(unsafe.withUnsafeBytes { setxattr(file.path, "org.d2rmobile.guest-name", $0.baseAddress, unsafe.count, 0, XATTR_NOFOLLOW) }, 0)
        XCTAssertThrowsError(try SaveArchive.entries(at: save))
    }

    func testTruncatedArchiveCannotReplaceExistingSave() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("valuable checkpoint".utf8).write(to: save.appendingPathComponent("slot"))
        let archive = root.appendingPathComponent("save.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        var truncated = try Data(contentsOf: archive); truncated.removeLast(4); try truncated.write(to: archive)
        XCTAssertThrowsError(try SaveArchive.restore(archive, save: save, backups: root.appendingPathComponent("backups"), titleID: title))
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("slot")), "valuable checkpoint")
    }

    func testUnreadableSubfolderCannotProducePartialBackup() throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission checks require an unprivileged user") }
        let root = try folder(), save = root.appendingPathComponent("save"), locked = save.appendingPathComponent("slot")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("progress".utf8).write(to: locked.appendingPathComponent("progress"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        let archive = root.appendingPathComponent("partial.switchsave")
        XCTAssertThrowsError(try SaveArchive.write(snapshot: save, to: archive, manifest: manifest()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testFailedRecoveryDirectoryLeavesNoRestoreStaging() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("cloud".utf8).write(to: save.appendingPathComponent("progress"))
        let archive = root.appendingPathComponent("save.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        try Data("local".utf8).write(to: save.appendingPathComponent("progress"))
        let backups = root.appendingPathComponent("backups")
        try Data("not a directory".utf8).write(to: backups)
        XCTAssertThrowsError(try SaveArchive.restore(archive, save: save, backups: backups, titleID: title))
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("progress")), "local")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".restore-") })
    }

    func testRecoveryDirectoryCannotBeInsideActiveSave() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("cloud".utf8).write(to: save.appendingPathComponent("progress"))
        let archive = root.appendingPathComponent("save.switchsave")
        try SaveArchive.write(snapshot: save, to: archive, manifest: manifest())
        try Data("local".utf8).write(to: save.appendingPathComponent("progress"))
        XCTAssertThrowsError(try SaveArchive.restore(archive, save: save, backups: save.appendingPathComponent("backups"), titleID: title))
        XCTAssertEqual(try String(contentsOf: save.appendingPathComponent("progress")), "local")
    }

    func testReusedSnapshotMetadataStillRejectsChangedBytes() throws {
        let root = try folder(), save = root.appendingPathComponent("save")
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        let file = save.appendingPathComponent("progress")
        try Data("first".utf8).write(to: file)
        let entries = try SaveArchive.entries(at: save)
        try Data("other".utf8).write(to: file)
        let archive = root.appendingPathComponent("save.switchsave")
        XCTAssertThrowsError(try SaveArchive.write(snapshot: save, to: archive, manifest: manifest(), entries: entries))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".archive-") })
    }

    func testCancelledBackupDoesNotPublishAnArchive() async throws {
        let root = try folder(), save = root.appendingPathComponent("save"), metadata = manifest()
        try FileManager.default.createDirectory(at: save, withIntermediateDirectories: true)
        try Data("progress".utf8).write(to: save.appendingPathComponent("progress"))
        let archive = root.appendingPathComponent("save.switchsave")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try SaveArchive.write(snapshot: save, to: archive, manifest: metadata)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }
}
