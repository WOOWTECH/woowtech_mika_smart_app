import XCTest

final class SelfConfigurationUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    func testManualAppearanceChangesActualThemePersistsAndModelPermissionDefaultsOff() {
        launch()
        let appearance = app.staticTexts["selfConfiguration.appliedAppearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        let systemAppearance = appearance.label
        let permission = app.switches["selfConfiguration.permission"]
        revealLearningElement(permission, in: app)
        XCTAssertEqual(permission.value as? String, "0")
        XCTAssertFalse(app.buttons["selfConfiguration.start"].exists)
        for (label, applied) in [("深色", "目前顯示：深色"), ("淺色", "目前顯示：淺色"), ("跟隨系統", systemAppearance), ("深色", "目前顯示：深色")] {
            let picker = app.descendants(matching: .any).matching(identifier: "selfConfiguration.appearance").firstMatch
            revealLearningElement(picker, in: app); picker.tap()
            let option = app.buttons[label].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", applied), object: appearance)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        app.terminate(); launch()
        XCTAssertEqual(app.staticTexts["selfConfiguration.appliedAppearance"].label, "目前顯示：深色")
        let restored = app.switches["selfConfiguration.permission"]
        revealLearningElement(restored, in: app)
        XCTAssertEqual(restored.value as? String, "0")
        let native = restored.switches.firstMatch
        (native.exists ? native : restored).tap()
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1"), object: restored)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed,
                       "The native permission switch must actually turn on.")
        // The conditional editor follows the permission section in a compact
        // Form. It may not enter the AX tree until the List scrolls to its row.
        let request = app.textViews["selfConfiguration.request"]
        revealLearningElement(request, in: app)
        XCTAssertTrue(request.exists)
        revealLearningElement(restored, in: app)
        (native.exists ? native : restored).tap()
        XCTAssertEqual(restored.value as? String, "0")
        XCTAssertFalse(app.buttons["selfConfiguration.start"].exists)
    }

    private func launch() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        app.launch()
        navigateMikaSection("settings", in: app)
        let link = app.buttons["settings.appearance"]
        revealLearningElement(link, in: app); link.tap()
    }
}
