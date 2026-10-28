import XCTest
@testable import SwitchSaveSync

final class CloudSaveStoreTests: XCTestCase {
    let title = "0100AC601DCA8000"
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func snapshot(_ root: URL, text: String) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url.appendingPathComponent("progress")); return url
    }
    func testOfflineCheckpointSurvivesRelaunchAndUnchangedSaveIsNotDuplicated() async throws {
        let root = try folder(), directory = root.appendingPathComponent("state"), cloud = root.appendingPathComponent("cloud")
        let offline = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { nil }, isEnabled: { true })
        do { try await offline.submit(snapshot: snapshot(root, text: "checkpoint")); XCTFail("Expected offline") } catch SaveError.unavailable {} catch { throw error }
        let queued = try SaveArchive.readManifest(directory.appendingPathComponent("outbox.switchsave"))
        let online = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        try await online.submit(snapshot: snapshot(root, text: "checkpoint"))
        let files = try FileManager.default.contentsOfDirectory(at: cloud.appendingPathComponent("Documents/Saves"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try SaveArchive.readManifest(XCTUnwrap(files.first)).id, queued.id)
        let state = try await online.localState(); XCTAssertEqual(state.clock, queued.clock)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("outbox.switchsave").path))
    }
    func testInterruptedStateWriteRecoversBeforeNextRevision() async throws {
        let root = try folder(), directory = root.appendingPathComponent("state"), cloud = root.appendingPathComponent("cloud")
        let original = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        let before = try await original.localState()
        try await original.submit(snapshot: snapshot(root, text: "first"))
        // Simulate termination after the outbox rename but before state commit.
        try JSONEncoder().encode(before).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        let restarted = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        try await restarted.submit(snapshot: snapshot(root, text: "second"))
        let after = try await restarted.localState()
        XCTAssertEqual(after.clock.values[before.device], 2)
        let rows = try FileManager.default.contentsOfDirectory(at: cloud.appendingPathComponent("Documents/Saves"), includingPropertiesForKeys: nil).map { try SaveArchive.readManifest($0) }
        XCTAssertEqual(rows.count, 1, "Unuploaded ancestors are replaced by the complete latest checkpoint")
        XCTAssertEqual(SaveManifest.heads(rows).count, 1)
    }
    func testQueuedCloudCopiesRemainBoundedWhileOffline() async throws {
        let root = try folder(), cloud = root.appendingPathComponent("cloud")
        let store = try CloudSaveStore(directory: root.appendingPathComponent("state"), titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        for i in 1...8 { try await store.submit(snapshot: snapshot(root, text: "checkpoint \(i)")) }
        let files = try FileManager.default.contentsOfDirectory(at: cloud.appendingPathComponent("Documents/Saves"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let restored = root.appendingPathComponent("restored")
        _ = try SaveArchive.extract(XCTUnwrap(files.first), to: restored, expectedTitle: title)
        XCTAssertEqual(try String(contentsOf: restored.appendingPathComponent("progress")), "checkpoint 8")
    }
    func testRestoreDecisionProtectsUnpublishedLocalProgressAndVersionChanges() {
        var state = SaveLocalState(); let device = state.device
        state.clock = SaveClock([device: 1]); state.contentHash = "last-synced"
        var manifest = SaveManifest(titleID: title, game: "Fixture", version: "1", device: device, deviceName: "Other device", clock: SaveClock([device: 2]))
        manifest.contentHash = "cloud"
        let record = CloudSaveRecord(manifest: manifest, url: URL(fileURLWithPath: "/fixture"), uploaded: true)
        if case .restore = SaveResolution.decide(records: [record], state: state, localHash: "last-synced", localExists: true, version: "1") {} else { XCTFail("Safe ancestor should restore") }
        if case .choose = SaveResolution.decide(records: [record], state: state, localHash: "unsynced-new-progress", localExists: true, version: "1") {} else { XCTFail("Local changes must require a choice") }
        if case .choose = SaveResolution.decide(records: [record], state: state, localHash: "last-synced", localExists: true, version: "2") {} else { XCTFail("Version changes must require a choice") }
        if case .adopt = SaveResolution.decide(records: [record], state: state, localHash: "cloud", localExists: true, version: "1") {} else { XCTFail("Identical progress should merge history") }
    }
    func testDisabledBackupsDoNotPublishAndReleaseSnapshot() async throws {
        let root = try folder(), cloud = root.appendingPathComponent("cloud")
        let store = try CloudSaveStore(directory: root.appendingPathComponent("state"), titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { false })
        let captured = try snapshot(root, text: "local only")
        try await store.submit(snapshot: captured)
        XCTAssertFalse(FileManager.default.fileExists(atPath: captured.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.path))
    }

    func testRestoringOlderContentDoesNotRewindRevisionHistory() async throws {
        let root = try folder(), cloud = root.appendingPathComponent("cloud"), directory = root.appendingPathComponent("state")
        let store = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        try await store.submit(snapshot: snapshot(root, text: "earlier chapter"))
        let old = root.appendingPathComponent("old.switchsave")
        try FileManager.default.copyItem(at: directory.appendingPathComponent("outbox.switchsave"), to: old)
        let manifest = try SaveArchive.readManifest(old)
        try await store.submit(snapshot: snapshot(root, text: "later chapter"))
        let current = try snapshot(root, text: "later chapter")
        try await store.restore(record: CloudSaveRecord(manifest: manifest, url: old, uploaded: true), save: current, backups: root.appendingPathComponent("backups"))
        try await store.acknowledge([manifest.clock])
        let captured = root.appendingPathComponent("capture")
        try FileManager.default.copyItem(at: current, to: captured)
        try await store.submit(snapshot: captured)
        let state = try await store.localState()
        XCTAssertEqual(state.clock.values[state.device], 3)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("progress")), "earlier chapter")
        let newest = try SaveArchive.readManifest(directory.appendingPathComponent("outbox.switchsave"))
        XCTAssertEqual(newest.contentHash, manifest.contentHash)
        XCTAssertTrue(newest.clock.dominates(SaveClock([state.device: 2])))
    }

    func testChangedCloudRecordCannotRestoreAnUnselectedSave() async throws {
        let root = try folder(), cloud = root.appendingPathComponent("cloud"), directory = root.appendingPathComponent("state")
        let store = try CloudSaveStore(directory: directory, titleID: title, game: "Fixture", version: "1", deviceName: "Phone", cloudRoot: { cloud }, isEnabled: { true })
        try await store.submit(snapshot: snapshot(root, text: "selected checkpoint"))
        let archive = directory.appendingPathComponent("outbox.switchsave")
        let selected = try SaveArchive.readManifest(archive)
        try await store.submit(snapshot: snapshot(root, text: "different checkpoint"))
        let local = try snapshot(root, text: "current local progress")
        let backups = root.appendingPathComponent("backups")
        do {
            try await store.restore(record: CloudSaveRecord(manifest: selected, url: archive, uploaded: true), save: local, backups: backups)
            XCTFail("Must restore exactly the checkpoint the user selected")
        } catch SaveError.invalid(let message) { XCTAssertTrue(message.contains("changed since it was selected")) }
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("progress")), "current local progress")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: backups.path).isEmpty)
    }

    func testMalformedOrOversizedLocalHistoryIsPreservedAndRejected() throws {
        let root = try folder(), stateURL = root.appendingPathComponent("state.json")
        var invalidDevice = SaveLocalState(); invalidDevice.device = "not a device ID"
        var invalidClock = SaveLocalState(); invalidClock.clock = SaveClock([invalidClock.device: 0])
        var invalidHash = SaveLocalState(); invalidHash.contentHash = "not a checksum"
        let fixtures = try [invalidDevice, invalidClock, invalidHash].map { try JSONEncoder().encode($0) } + [Data(repeating: 32, count: 64 * 1024 + 1)]
        for bytes in fixtures {
            try bytes.write(to: stateURL)
            XCTAssertThrowsError(try CloudSaveStore(directory: root, titleID: title, game: "Fixture", version: "1", deviceName: "Phone"))
            XCTAssertEqual(try Data(contentsOf: stateURL), bytes)
        }
    }

    func testCancelledMetadataScanDoesNotStartFileReads() async {
        let count = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var reads = 0
            _ = CloudSaveStore.readRecords([URL(fileURLWithPath: "/unused.switchsave")]) { _ in
                reads += 1; return nil
            }
            return reads
        }.value
        XCTAssertEqual(count, 0, "A superseded scan must not start file coordination")
    }

    func testMetadataScanStopsAfterCancellationDuringARead() async {
        let device = UUID().uuidString.lowercased()
        let manifest = SaveManifest(titleID: title, game: "Fixture", version: "1", device: device,
                                    deviceName: "Phone", clock: SaveClock([device: 1]))
        let record = CloudSaveRecord(manifest: manifest, url: URL(fileURLWithPath: "/fixture.switchsave"), uploaded: true)
        let result = await Task {
            var reads = 0
            let rows = CloudSaveStore.readRecords(Array(repeating: record.url, count: 20)) { _ in
                reads += 1
                if reads == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                return record
            }
            return (reads, rows.count)
        }.value
        XCTAssertEqual(result.0, 3, "Cancellation must stop the remaining coordinated reads")
        XCTAssertEqual(result.1, 0, "A canceled scan must not publish a partial list")
    }
}
