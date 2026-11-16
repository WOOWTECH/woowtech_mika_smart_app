import XCTest

final class SelfConfigurationUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    /// Settings › 語言與外觀 is Play's single-choice list; only the user
    /// changes the appearance.
    func testManualAppearanceChoicePersistsWithoutModelPermission() {
        launch()
        let rows = [("system", "跟隨系統"), ("light", "一直淺色"), ("dark", "一直深色")]
        for (value, title) in rows {
            let row = app.buttons["selfConfiguration.appearance." + value]
            revealLearningElement(row, in: app)
            XCTAssertTrue(row.label.hasPrefix(title), value)
        }
        assertSelected("system")
        XCTAssertTrue(app.buttons["selfConfiguration.appearance.system"].label.contains("裝置是淺色就淺色，深色就深色"))
        // The scheme the page really renders with, not only the selected row.
        let applied = app.staticTexts["selfConfiguration.appliedScheme"]
        XCTAssertTrue(applied.waitForExistence(timeout: 5))
        let systemScheme = applied.label
        for (value, scheme) in [("dark", "dark"), ("light", "light"), ("system", systemScheme), ("dark", "dark")] {
            let row = app.buttons["selfConfiguration.appearance." + value]
            revealLearningElement(row, in: app); row.tap()
            assertSelected(value)
            let rendered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", scheme), object: applied)
            XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 5), .completed, value)
        }
        app.terminate(); launch()
        assertSelected("dark")
        XCTAssertEqual(app.staticTexts["selfConfiguration.appliedScheme"].label, "dark", "dark survives relaunch")
    }

    private func assertSelected(_ value: String) {
        let row = app.buttons["selfConfiguration.appearance." + value]
        revealLearningElement(row, in: app)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, value)
    }

    private func launch() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        app.launch()
        navigateMikaSection("settings", in: app)
        let link = app.buttons["settings.appearance"]
        revealLearningElement(link, in: app); link.tap()
    }
}
