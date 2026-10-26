import XCTest
import UIKit
@testable import iSwitch

final class CoverArtTests: XCTestCase {
    @MainActor
    func testCoverDecoderBoundsPixelsAndRejectsInvalidFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("cover.jpg")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3072, height: 1536), format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3072, height: 1536))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.9)).write(to: source)
        let decoded = await Task.detached { CoverImageLoader.load(source) }.value
        let pixels = try XCTUnwrap(decoded?.cgImage)
        XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), 768)
        XCTAssertEqual(pixels.width, pixels.height * 2)

        let invalid = directory.appendingPathComponent("invalid.jpg")
        try Data("Not an image".utf8).write(to: invalid)
        XCTAssertNil(CoverImageLoader.load(invalid))
        let oversized = directory.appendingPathComponent("oversized.jpg")
        try Data(repeating: 0, count: 512 * 1024 + 1).write(to: oversized)
        XCTAssertNil(CoverImageLoader.load(oversized))
    }
}
