import XCTest

/// An actual XCUI tap exercises the production system URL action. The local
/// WebKit fixture has a public HTTPS identity but makes no external request;
/// only the explicit handoff lets iOS open the default browser.
final class BrowserExternalOpenUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    override func tearDownWithError() throws { app.terminate() }

    func testNativeMoreMenuTapHandsOffTheExactVisibleHashRoute() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        app.launch()
        navigateMikaSection("browser", in: app)

        let url = "https://research.example.invalid/workspace-one#/docs/42"
        let address = app.textFields["browser.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(address.isHittable)
        address.tap()
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

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertNotEqual(safari.state, .runningForeground)
        handoff.tap()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20),
                      "The native tap must invoke iOS's external URL action")
        XCTAssertNotEqual(app.state, .runningForeground)
        let screenshot = XCTAttachment(screenshot: safari.screenshot())
        screenshot.name = "Actual external App after browser handoff"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
