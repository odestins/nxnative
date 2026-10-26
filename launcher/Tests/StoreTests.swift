import XCTest
@testable import iSwitchCore

final class StoreTests: XCTestCase {
    func testBothRequestedStoresAreAvailable() {
        XCTAssertEqual(Set(StoreDestination.allCases.map { $0.url.absoluteString }), ["https://nsvault.me/", "https://romsns.com/"])
        XCTAssertEqual(Set(StoreDestination.allCases.map(\.id)).count, 2)
    }
}
