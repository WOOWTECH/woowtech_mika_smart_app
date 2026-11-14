import XCTest
import CoreGraphics

final class BrowserWorkspaceUITests: XCTestCase {
    private var app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "workspace-fixture-AX"; tree.lifetime = .keepAlways; add(tree)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "workspace-fixture"; shot.lifetime = .keepAlways; add(shot)
        }
        app.terminate()
    }
    func testStartPageFavoritesRecentAndRealClosePageFlow() {
        launch(reset: true)
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].exists)
        let emptyHistory = app.staticTexts["browser.start.history.empty"]
        XCTAssertTrue(emptyHistory.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyHistory.label, "尚無瀏覽歷史")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.start.history.open.")).count, 0)
        XCTAssertTrue(app.buttons["browser.favorites.add"].exists)
        let emptyStart = XCTAttachment(screenshot: app.screenshot())
        emptyStart.name = "browser-android-empty-start"; emptyStart.lifetime = .keepAlways; add(emptyStart)
        open("workspace-one")
        let loadedPage = XCTAttachment(screenshot: app.screenshot())
        loadedPage.name = "browser-android-loaded-page"; loadedPage.lifetime = .keepAlways; add(loadedPage)
        addFavoriteFromMore()
        XCTAssertTrue(app.buttons["browser.home"].waitForExistence(timeout: 5))
        app.buttons["browser.home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["browser.status"].label, "輸入網址開始瀏覽")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.favorite.open.")).count, 1)
        let recent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.start.history.open.")).firstMatch
        XCTAssertTrue(recent.exists)
        recent.tap()
        XCTAssertTrue(dom("Workspace first").waitForExistence(timeout: 75))
        app.buttons["browser.closePage"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].waitForExistence(timeout: 5))
        app.buttons["browser.start.history.clear"].tap()
        let confirmation = app.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %d OR elementType == %d) AND label == %@",
            XCUIElement.ElementType.sheet.rawValue, XCUIElement.ElementType.other.rawValue,
            "清除瀏覽歷史？書籤與網站登入資料會保留。")).firstMatch
        // iOS 26 may expose the same action as nested AX buttons. Keep the
        // exact dialog, identifier and label while selecting one representation.
        let clear = confirmation.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            "browser.start.history.confirmClear", "清除歷史")).firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); XCTAssertEqual(clear.label, "清除歷史"); clear.tap()
        XCTAssertTrue(emptyHistory.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyHistory.label, "尚無瀏覽歷史")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.favorite.open.")).count, 1)
        XCTAssertFalse(app.buttons["browser.library"].exists, "Like the Play build, the browser has no library sheet.")
    }

    func testAskMikaEntryOpensExistingResearchOnlyForCurrentReadablePage() {
        launch(reset: true)
        let entry = app.buttons["browser.pageAsk.open"]
        XCTAssertFalse(entry.exists, "A start page has no inspected website to ask about.")
        open("workspace-one")
        XCTAssertTrue(entry.waitForExistence(timeout: 75))
        XCTAssertEqual(entry.label, "問渥屋助理研究此網站")
        XCTAssertEqual(entry.value as? String, "research.example.invalid")
        XCTAssertTrue(dom("Workspace first").exists)
        let address = app.textFields["browser.address"]
        let pageURL = "https://research.example.invalid/workspace-one"
        XCTAssertEqual(address.value as? String, pageURL)

        entry.tap()
        let goal = app.descendants(matching: .any).matching(identifier: "browser.goal").firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.start"].isEnabled,
                       "Opening the entry must not start a model request or bypass configuration.")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "browser.answer").firstMatch.exists)
        app.buttons["browser.research.close"].tap()
        XCTAssertEqual(address.value as? String, pageURL)
        XCTAssertTrue(dom("Workspace first").exists)
        XCTAssertTrue(entry.exists)

        app.buttons["browser.closePage"].tap()
        XCTAssertFalse(entry.exists)
        open("workspace-one?q=manual#section")
        XCTAssertFalse(entry.exists, "A manual-only callback/query page is not a readable research page.")
        XCTAssertFalse(app.buttons["browser.research"].isEnabled)
    }

    func testFavoriteSurvivesRelaunchAndEditRemovesIt() {
        launch(reset: true); open("workspace-one")
        addFavoriteFromMore()
        let favorites = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.favorite.open."))
        app.buttons["browser.home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(favorites.count, 1)
        launch(reset: false)
        if app.buttons["browser.closePage"].waitForExistence(timeout: 10) { app.buttons["browser.closePage"].tap() }
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(favorites.firstMatch.waitForExistence(timeout: 5), "The favorite is stored encrypted and survives a relaunch.")
        XCTAssertEqual(favorites.count, 1)
        app.buttons["browser.favorites.edit"].tap()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.favorite.remove.")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: favorites)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
    func testManualQueryPageAndRealJavaScriptDialog() {
        launch(reset: true); open("workspace-one?q=manual#section")
        XCTAssertFalse(app.buttons["browser.research"].isEnabled)
        XCTAssertFalse(app.buttons["browser.interactions"].isEnabled)
        app.webViews.buttons["Confirm fixture"].tap()
        XCTAssertTrue(app.staticTexts["browser.dialog.message"].waitForExistence(timeout: 5))
        app.buttons["browser.dialog.cancel"].tap()
        XCTAssertTrue(dom("CANCELLED").waitForExistence(timeout: 5))
        app.webViews.buttons["Confirm fixture"].tap()
        app.buttons["browser.dialog.accept"].tap()
        XCTAssertTrue(dom("CONFIRMED").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["browser.error"].exists)
    }
    private func launch(reset: Bool) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launch()
        navigateMikaSection("browser", in: app)
    }
    private func open(_ path: String) {
        let field = app.textFields["browser.address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        if let value = field.value as? String, value.hasPrefix("https://") { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText("https://research.example.invalid/" + path + "\n")
        let title = path.hasPrefix("workspace-two") ? "Workspace second" : "Workspace first"
        XCTAssertTrue(dom(title).waitForExistence(timeout: 75))
    }
    /// Play's More › Add to favorites; the sheet closes after the choice.
    private func addFavoriteFromMore() {
        let more = app.buttons["browser.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        let add = app.buttons["browser.more.addFavorite"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: add)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }
    private func dom(_ text: String) -> XCUIElement { app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch }
}
