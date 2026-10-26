import XCTest
@testable import iSwitchCore

final class ControllerNavigationTests: XCTestCase {
    func testThresholdJitterDoesNotBecomeRepeatedPresses() {
        var navigation = ControllerNavigation()
        XCTAssertEqual(navigation.update(x: 0.56, y: 0, now: 1), .right)
        XCTAssertNil(navigation.update(x: 0.53, y: 0, now: 1.05))
        XCTAssertNil(navigation.update(x: 0.56, y: 0, now: 1.1))
        XCTAssertEqual(navigation.update(x: 0.54, y: 0, now: 1.41), .right)
        XCTAssertNil(navigation.update(x: 0.34, y: 0, now: 1.42))
        XCTAssertEqual(navigation.update(x: 0.56, y: 0, now: 1.43), .right)
    }

    func testDiagonalJitterKeepsAxisUntilIntentionalChange() {
        var navigation = ControllerNavigation()
        XCTAssertEqual(navigation.update(x: 0.7, y: 0.6, now: 1), .right)
        XCTAssertNil(navigation.update(x: 0.7, y: 0.72, now: 1.05))
        XCTAssertNil(navigation.update(x: 0.72, y: 0.7, now: 1.1))
        XCTAssertEqual(navigation.update(x: 0.6, y: 0.9, now: 1.15), .up)
        XCTAssertEqual(navigation.update(x: 0, y: -1, now: 1.2), .down)
    }

    func testInvalidInputResetsHeldDirection() {
        var navigation = ControllerNavigation()
        XCTAssertEqual(navigation.update(x: 1, y: 0, now: 1), .right)
        XCTAssertNil(navigation.update(x: .nan, y: 0, now: 1.05))
        XCTAssertEqual(navigation.update(x: 1, y: 0, now: 1.1), .right)
        XCTAssertNil(navigation.update(x: 1, y: .infinity, now: 1.2))
        XCTAssertNil(navigation.update(x: 1, y: 0, now: .nan))
    }
}
