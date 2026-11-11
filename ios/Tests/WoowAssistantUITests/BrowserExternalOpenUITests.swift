import XCTest

/// An actual XCUI tap exercises the system URL action. The local WebKit
/// fixture makes no external request until that tap. This UI case proves the
/// App backgrounds after the action; it cannot inspect the default browser's
/// actual URL. A hosted action-boundary test captures the exact URL argument.
final class BrowserExternalOpenUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    override func tearDownWithError() throws { app.terminate() }

    func testNativeMoreMenuTapLeavesAppForSystemHandoff() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        app.launch()
        navigateMikaSection("browser", in: app)

        let url = "https://research.example.invalid/workspace-one#/docs/42"
        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(address.isHittable)
        address.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The native address keyboard must appear before typeText")
        address.typeText(url + "\n")
        let page = app.webViews.staticTexts["Workspace first"]
        XCTAssertTrue(page.waitForExistence(timeout: 75))
        XCTAssertEqual(address.value as? String, url)

        let more = app.buttons["browser.more"]
        XCTAssertTrue(more.isHittable)
        more.tap()
        let handoff = app.buttons["browser.more.openOutside"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 5))
        XCTAssertTrue(handoff.isEnabled)
        XCTAssertTrue(handoff.isHittable)
        XCTAssertEqual(handoff.value as? String, url,
                       "The real button must expose the exact checked hash-route destination")

        handoff.tap()
        let leftForeground = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.app.state == .runningBackground || self.app.state == .runningBackgroundSuspended
            }, object: nil
        )], timeout: 20)
        let appStateAfterWait = app.state.rawValue
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "System foreground after browser handoff; URL unverified"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(leftForeground, .completed,
                       "The App must remain running in the background after the native system URL action; state after wait: \(appStateAfterWait)")
    }
}
