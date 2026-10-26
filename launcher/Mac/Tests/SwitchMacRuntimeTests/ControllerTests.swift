import XCTest
import SwitchMacRuntime

final class ControllerTests: XCTestCase {
    func testDeadzoneInitialPressHoldAndRelease() {
        var nav = ControllerNavigation()
        XCTAssertNil(nav.update(x: 0.3, y: -0.2, now: 0))
        XCTAssertEqual(nav.update(x: 1, y: 0, now: 1), .right)
        XCTAssertNil(nav.update(x: 1, y: 0, now: 1.1))
        XCTAssertEqual(nav.update(x: 1, y: 0, now: 1.41), .right)
        XCTAssertNil(nav.update(x: 1, y: 0, now: 1.45))
        XCTAssertEqual(nav.update(x: 1, y: 0, now: 1.56), .right)
        XCTAssertNil(nav.update(x: 0, y: 0, now: 1.57))
        XCTAssertEqual(nav.update(x: 1, y: 0, now: 1.58), .right)
    }
    func testDirectionChangesAndResetDoNotWaitForRepeat() {
        var nav = ControllerNavigation()
        XCTAssertEqual(nav.update(x: 1, y: 0, now: 1), .right)
        XCTAssertEqual(nav.update(x: 0, y: -1, now: 1.01), .down)
        XCTAssertEqual(nav.update(x: -0.7, y: 0.2, now: 1.02), .left)
        nav.reset()
        XCTAssertEqual(nav.update(x: -1, y: 0, now: 1.03), .left)
        XCTAssertEqual(nav.update(x: 0.6, y: 0.9, now: 1.04), .up)
    }
}
