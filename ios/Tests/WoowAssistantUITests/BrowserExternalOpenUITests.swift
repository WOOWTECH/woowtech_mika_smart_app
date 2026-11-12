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
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestExternalOpenDiagnostics"]
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

        let tapStarted = ProcessInfo.processInfo.systemUptime
        handoff.tap()
        let tapReturned = ProcessInfo.processInfo.systemUptime
        var observedStates: [String] = []
        let leftForeground = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let state = self.app.state
                let sample = "\(state.rawValue)"
                if observedStates.last != sample { observedStates.append(sample) }
                return state == .runningBackground || state == .runningBackgroundSuspended
            }, object: nil
        )], timeout: 20)
        let appStateAfterWait = app.state.rawValue
        // Never reactivate the App to read diagnostics: doing so would destroy
        // the state we are testing. NSLog also records the production callback.
        var observation = "unavailable_while_not_foreground"
        if appStateAfterWait == XCUIApplication.State.runningForeground.rawValue {
            observation = ["browser.externalHandoff.observation", "browser.externalHandoff.sheetObservation"].map { id in
                let field = app.staticTexts[id].firstMatch
                return "\(id)=\(field.exists ? (field.value as? String ?? "no_accessibility_value") : "not_in_accessibility_tree")"
            }.joined(separator: ",")
        }
        // These are observations only: another default browser may be in use.
        let safariState = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").state.rawValue
        let springboardState = XCUIApplication(bundleIdentifier: "com.apple.springboard").state.rawValue
        let diagnostics = XCTAttachment(string: "tapStarted=\(tapStarted);tapReturned=\(tapReturned);states=\(observedStates.joined(separator: ","));stateAfterWait=\(appStateAfterWait);safariState=\(safariState);springboardState=\(springboardState);trace=\(observation)")
        diagnostics.name = "External handoff action and application states"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "System foreground after browser handoff; URL unverified"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(leftForeground, .completed,
                       "The App must remain running in the background after the native system URL action; state after wait: \(appStateAfterWait)")
    }
}
