import XCTest

final class HomeTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPerformanceHUDPreferencePersists() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        app.buttons["dock-settings"].tap()
        let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); overview.name = "Settings overview dark"; overview.lifetime = .keepAlways; add(overview)
        let toggle = app.switches["performanceHUD"]
        for _ in 0..<3 { if toggle.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let expected = (toggle.value as? String) == "1" ? "0" : "1"
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let changed = NSPredicate(format: "value == %@", expected)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: toggle)], timeout: 5), .completed)
        let settings = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); settings.name = "Performance HUD setting"; settings.lifetime = .keepAlways; add(settings)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["dock-settings"].tap()
        for _ in 0..<3 { if toggle.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertEqual(toggle.value as? String, expected)
    }

    @MainActor
    func testSettingsNavigationAndAppearance() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        app.buttons["dock-settings"].tap()
        app.buttons["settingsProfile"].tap()
        XCTAssertTrue(app.buttons["chooseProfilePhoto"].waitForExistence(timeout: 5))
        app.buttons["BackButton"].tap()
        reveal(app.buttons["settingsImports"], in: app)
        app.buttons["settingsImports"].tap()
        XCTAssertTrue(app.buttons["importGameFile"].waitForExistence(timeout: 5))
        app.buttons["BackButton"].tap()
        reveal(app.buttons["settingsAddGames"], in: app)
        app.buttons["settingsAddGames"].tap()
        app.buttons["importCards"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["BackButton"].tap()
        reveal(app.buttons["cloudSavesSettings"], in: app)
        app.buttons["cloudSavesSettings"].tap()
        XCTAssertTrue(app.navigationBars["iCloud saves"].waitForExistence(timeout: 5))
        app.buttons["BackButton"].tap()
        reveal(app.buttons["appearancePicker"], in: app)
        app.buttons["appearancePicker"].tap()
        app.buttons["Light"].tap()
        snapshot("Settings light appearance")
        app.buttons["appearancePicker"].tap()
        app.buttons["Dark"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 10), .completed)
        snapshot("Settings landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { _, _ in app.frame.height > app.frame.width }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: nil)], timeout: 10), .completed)
        app.buttons["closePanel"].tap()
    }

    @MainActor
    func testSettingsAndJoinWithLargerText() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library", "--gamechat-preview",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["dock-settings"].tap()
        reveal(app.switches["performanceHUD"], in: app)
        snapshot("Settings larger text")
        app.buttons["closePanel"].tap()
        app.buttons["dock-chat"].tap()
        let join = app.buttons["joinChat"]
        for _ in 0..<4 { if join.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(join.isHittable)
        snapshot("Chat larger text")
        join.tap()
        XCTAssertTrue(app.alerts["Join Chat"].waitForExistence(timeout: 5))
        app.alerts["Join Chat"].buttons["Cancel"].tap()
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        for _ in 0..<10 {
            let top = max(list.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 8
            let bottom = list.frame.maxY - 8
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { break }
            // Small drags keep a row from jumping behind the floating iPad toolbar.
            let downward = element.exists && element.frame.minY < top
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.35 : 0.65))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.65 : 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testProfilePhotoPicker() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        app.buttons["Your profile"].tap()
        let choose = app.buttons["chooseProfilePhoto"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        let profile = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); profile.name = "Profile photo controls"; profile.lifetime = .keepAlways; add(profile)
        choose.tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEmptyLibraryAndPreviewBothOrientations() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        XCTAssertTrue(app.buttons["addGamesPrimary"].waitForExistence(timeout: 10))
        app.buttons["previewLibrary"].tap()
        XCTAssertTrue(app.buttons["game-F000000000000001"].waitForExistence(timeout: 5))
        app.buttons["startGame"].tap()
        XCTAssertTrue(app.alerts["Layout preview"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        let portraitReady = NSPredicate { _, _ in app.frame.height > app.frame.width && app.buttons["dock-settings"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portraitReady, object: nil)], timeout: 10), .completed)
        assertHomeControlsFit(app)
        let portrait = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); portrait.name = "Switch portrait preview"; portrait.lifetime = .keepAlways
        add(portrait)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["dock-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let landscapeReady = NSPredicate { _, _ in app.frame.width > app.frame.height && app.buttons["dock-settings"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscapeReady, object: nil)], timeout: 10), .completed)
        assertHomeControlsFit(app)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); landscape.name = "iSwitch landscape preview"; landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portraitReady, object: nil)], timeout: 10), .completed)
        app.buttons["exitPreview"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["addGamesPrimary"].waitForExistence(timeout: 5))
    }

    @MainActor private func assertHomeControlsFit(_ app: XCUIApplication) {
        let actions = ["chat", "shop", "controllers", "sources", "settings"].map { app.buttons["dock-\($0)"] }
        for button in actions {
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(app.frame.contains(button.frame), "Navigation must fit in either orientation")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        for (left, right) in zip(actions, actions.dropFirst()) {
            XCTAssertLessThanOrEqual(left.frame.maxX, right.frame.minX)
        }
        XCTAssertLessThan(app.buttons["game-F000000000000001"].frame.maxY, actions[0].frame.minY)
        XCTAssertLessThan(actions[0].frame.maxY, app.buttons["startGame"].frame.minY)
        XCTAssertGreaterThanOrEqual(app.buttons["startGame"].frame.height, 44)
        if UIDevice.current.userInterfaceIdiom == .phone && app.frame.height > app.frame.width {
            XCTAssertLessThan(app.buttons["game-F000000000000001"].frame.width, app.frame.width * 0.5,
                              "Portrait covers should leave room to see the next game")
            XCTAssertLessThan(app.buttons["startGame"].frame.minY - actions[0].frame.maxY, 72,
                              "The navbar should stay near the bottom controls")
        }
    }

    @MainActor
    func testAddProfilePersistsAndDoesNotPretendToBeInstalled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        app.buttons["addGamesPrimary"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Wonder")
        let add = app.buttons["Add Super Mario Bros. Wonder to preparation list"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.alerts["Added to your library"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        // iOS's active search presentation hides the navigation toolbar until it closes.
        if app.buttons["close"].exists { app.buttons["close"].tap() }
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        XCTAssertTrue(app.buttons["closePanel"].waitForExistence(timeout: 5))
        app.buttons["closePanel"].tap()
        XCTAssertTrue(app.buttons["game-010015100B514000"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["game-010015100B514000"].waitForExistence(timeout: 5))
        app.buttons["startGame"].tap()
        XCTAssertTrue(app.navigationBars["Getting ready"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPhoneImportsAndManualGameCard() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch()
        app.buttons["addGamesPrimary"].tap()
        app.buttons["importFromIPhone"].tap()
        for identifier in ["importGameFile", "importProdKeys", "importFirmware"] {
            let button = app.buttons[identifier]
            if !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        }
        let snapshot = XCTAttachment(screenshot: app.screenshot()); snapshot.name = "iPhone import controls"; snapshot.lifetime = .keepAlways; add(snapshot)
        app.buttons["BackButton"].tap()
        app.buttons["Add a game manually"].tap()
        let name = app.textFields["manualGameName"], id = app.textFields["manualTitleID"]
        name.tap(); name.typeText("My manual game")
        id.tap(); id.typeText("0100000000000123")
        if app.buttons["Hide keyboard"].waitForExistence(timeout: 5) { app.buttons["Hide keyboard"].tap() }
        app.buttons["saveManualGame"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["closePanel"].tap()
        XCTAssertTrue(app.buttons["game-0100000000000123"].waitForExistence(timeout: 5))
    }
}
