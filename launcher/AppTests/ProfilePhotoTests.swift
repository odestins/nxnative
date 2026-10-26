import XCTest
import UIKit
import ImageIO
@testable import iSwitch

final class ProfilePhotoTests: XCTestCase {
    @MainActor
    func testPhotoIsDownsampledPersistsAndSurvivesInvalidReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.jpg")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 1024))
        let image = renderer.image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024)) }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.95)).write(to: source)
        let store = ProfilePhotoStore(directory: root.appendingPathComponent("Profile"))
        let saved = try await store.save(source)
        let preview = try XCTUnwrap(UIImage(data: saved)?.cgImage)
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 512)
        XCTAssertLessThanOrEqual(saved.count, 256 * 1024)
        let restored = try await ProfilePhotoStore(directory: root.appendingPathComponent("Profile")).load()
        XCTAssertEqual(restored, saved)
        let bad = root.appendingPathComponent("bad.jpg"); try Data("not an image".utf8).write(to: bad)
        do { _ = try await store.save(bad); XCTFail("Invalid image must not replace the profile photo") } catch {}
        let retained = try await store.load(); XCTAssertEqual(retained, saved)
        try await store.remove()
        let removed = try await store.load(); XCTAssertNil(removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}
