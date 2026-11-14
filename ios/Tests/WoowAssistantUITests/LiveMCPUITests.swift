import XCTest

// Only the manual live-MCP workflow injects this secret. Never attach screenshots,
// emit app debugDescription, or publish live xcresult/xctestrun files.
final class LiveMCPUITests: XCTestCase {
    private let namespace = UUID().uuidString
    private var launched = false
    private var initialLaunchCompleted = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        guard let endpoint = ProcessInfo.processInfo.environment["WOOW_LIVE_MCP_URL"], !endpoint.isEmpty else {
            throw XCTSkip("Private MCP test configuration was not supplied.")
        }
    }

    override func tearDownWithError() throws {
        guard launched else { return }
        let app = XCUIApplication()
        try LiveMCPNativeLifecycle.stopAndShowHome(app)
        guard initialLaunchCompleted else {
            XCTFail("LIVE_MCP_CLEANUP initial launch did not complete; namespace cleanup is unverified and isolated simulator removal is required.")
            return
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage"]
        app.launchEnvironment = [:]
        app.launch()
        try LiveMCPNativeLifecycle.requireForeground(app)
        navigateMikaSection("tools", in: app)
        XCTAssertTrue(app.staticTexts["mcp.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "尚未設定 MCP")
        try LiveMCPNativeLifecycle.stopAndShowHome(app)
    }

    func testRealDiscoveryDisconnectAndReconnect() throws {
        let endpoint = try XCTUnwrap(ProcessInfo.processInfo.environment["WOOW_LIVE_MCP_URL"])
        let app = XCUIApplication()
        try LiveMCPNativeLifecycle.stopAndShowHome(app)
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage", "-LiveMCPUITest"]
        app.launchEnvironment = ["WOOW_LIVE_MCP_URL": endpoint]
        launched = true
        app.launch()
        try LiveMCPNativeLifecycle.requireForeground(app)
        initialLaunchCompleted = true
        navigateMikaSection("tools", in: app)
        XCTAssertTrue(app.staticTexts["mcp.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "端點已儲存，尚未驗證連線")
        XCTAssertFalse(app.staticTexts["mcp.testIsolation"].exists)
        func assertConnected(_ step: String) {
            let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.staticTexts["mcp.status"].label == "已連線，目錄擷取完成" || app.staticTexts["mcp.error"].exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 95), .completed, step)
            XCTAssertFalse(app.staticTexts["mcp.error"].exists, "Live MCP discovery failed: \(step)")
            XCTAssertEqual(app.staticTexts["mcp.status"].label, "已連線，目錄擷取完成")
            revealLearningElement(app.staticTexts["mcp.toolCount"], in: app, visibility: .readableText)
            XCTAssertTrue(app.staticTexts["mcp.toolCount"].label.contains("個"))
            XCTAssertFalse(app.staticTexts["mcp.toolCount"].label.contains("：0 個"))
        }
        revealLearningElement(app.buttons["mcp.connect"], in: app)
        app.buttons["mcp.connect"].tap()
        assertConnected("first connect")
        // Like the Play build, leaving the app does not cost the setup: the
        // connection comes back on its own, with the catalog, when it returns.
        XCUIDevice.shared.press(.home)
        app.activate()
        assertConnected("reconnect after the background")
        print("LIVE_MCP_RECONNECT completed=true")
        // isHittable alone can include a List row covered by the native
        // navigation bar or keyboard. Require its full frame in the actual
        // content viewport and perform one native tap.
        revealLearningElement(app.buttons["mcp.disconnect"], in: app)
        app.buttons["mcp.disconnect"].tap()
        let disconnected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["mcp.status"].label == "已中斷本機連線"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [disconnected], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["mcp.toolCount"].exists, "Disconnect must clear the actual discovered catalog.")
    }
}
