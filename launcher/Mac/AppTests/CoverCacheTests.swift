import XCTest
import CoreGraphics
@testable import SwitchMacApp

final class CoverCacheTests: XCTestCase {
    private func pixels() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                             bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    @MainActor
    func testPixelBudgetEvictsLeastRecentlyUsedCover() throws {
        let image = try pixels(), bytes = image.bytesPerRow * image.height
        var cache = MacCoverCache(maximumBytes: bytes * 2, countLimit: 32)
        cache.insert(image, for: "first", source: "one")
        cache.insert(image, for: "second", source: "two")
        XCTAssertNotNil(cache.image(for: "first", source: "one"))
        cache.insert(image, for: "third", source: "three")
        XCTAssertEqual(Set(cache.images.keys), ["first", "third"])
        XCTAssertEqual(cache.residentBytes, bytes * 2)
    }

    @MainActor
    func testSourceInvalidationAndCountLimit() throws {
        let image = try pixels()
        var cache = MacCoverCache(maximumBytes: 4096, countLimit: 2)
        for number in 1...3 { cache.insert(image, for: "\(number)", source: "source-\(number)") }
        XCTAssertEqual(cache.images.count, 2)
        XCTAssertNil(cache.image(for: "2", source: "replacement"))
        cache.retainSources(["2": "replacement", "3": "source-3"])
        XCTAssertEqual(Set(cache.images.keys), ["3"])
        cache.insert(image, for: "2", source: "replacement")
        XCTAssertNotNil(cache.image(for: "2", source: "replacement"))
        cache.retainSources([:])
        XCTAssertTrue(cache.images.isEmpty)
        XCTAssertEqual(cache.residentBytes, 0)
    }
}
