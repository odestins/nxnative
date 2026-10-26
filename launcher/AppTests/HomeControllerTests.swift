import XCTest
import iSwitchCore
@testable import iSwitch

final class HomeControllerTests: XCTestCase {
    @MainActor
    func testHomeControllerMovesBetweenCardsAndDockWithoutChangingSelectedGame() {
        let model = LibraryModel()
        model.isPreview = true
        model.selectedID = LibraryModel.previewGames[0].id
        model.moveController(.right)
        XCTAssertEqual(model.selectedID, LibraryModel.previewGames[1].id)
        model.moveController(.down)
        XCTAssertEqual(model.focusedDock, .chat)
        model.moveController(.right)
        XCTAssertEqual(model.focusedDock, .shop)
        XCTAssertEqual(model.selectedID, LibraryModel.previewGames[1].id)
        model.moveController(.up)
        XCTAssertNil(model.focusedDock)
        model.moveController(.left)
        XCTAssertEqual(model.selectedID, LibraryModel.previewGames[0].id)
    }

    @MainActor
    func testControllerClampsDockAndCannotNavigateBehindPanelOrAlert() {
        let model = LibraryModel()
        model.moveController(.down)
        model.moveController(.left)
        XCTAssertEqual(model.focusedDock, .chat)
        for _ in 0..<20 { model.moveController(.right) }
        XCTAssertEqual(model.focusedDock, .settings)
        model.panel = .profile
        model.moveController(.left)
        XCTAssertEqual(model.focusedDock, .settings)
        model.panel = nil
        model.notice = AppNotice(title: "Test", message: "Test")
        model.moveController(.up)
        XCTAssertEqual(model.focusedDock, .settings)
        model.notice = nil
        model.select("F000000000000001")
        XCTAssertNil(model.focusedDock)
    }
}
