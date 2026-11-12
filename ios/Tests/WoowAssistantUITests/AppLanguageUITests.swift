import XCTest

/// Actual settings UI acceptance. Never sets defaults/bindings or overrides a
/// product DEBUG locale. Each case owns fresh storage; model requests stay off.
final class AppLanguageUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    func testExplicitEnglishPersistsAndPreservesAppearancePermissionAndDraft() {
        launch(systemLanguages: "(zh-Hant)")
        choose("selfConfiguration.appearance", option: "深色")
        let permission = app.switches["selfConfiguration.permission"]
        revealLearningElement(permission, in: app)
        XCTAssertEqual(permission.value as? String, "0")
        let native = permission.switches.firstMatch
        (native.exists ? native : permission).tap()
        let draft = app.textViews["selfConfiguration.request"]
        revealLearningElement(draft, in: app); draft.tap(); draft.typeText("保留 Tea")
        app.buttons["selfConfiguration.keyboard.done"].tap()
        choose("settings.language", option: "English")
        exactLabel("settings.language.resolved", "Current interface: English")
        exactLabel("selfConfiguration.appliedAppearance", "Currently displayed: Dark")
        revealLearningElement(permission, in: app)
        XCTAssertEqual(permission.value as? String, "1")
        revealLearningElement(draft, in: app)
        XCTAssertEqual(draft.value as? String, "保留 Tea")
        exactLabel("selfConfiguration.status", "No appearance change has been requested.")
        app.terminate(); launch(systemLanguages: "(zh-Hant)")
        exactLabel("settings.language.resolved", "Current interface: English")
        exactLabel("selfConfiguration.appliedAppearance", "Currently displayed: Dark")
        revealLearningElement(permission, in: app)
        XCTAssertEqual(permission.value as? String, "1")
    }

    func testSimplifiedChineseAndSystemFollowActualPreferredLanguages() {
        launch(systemLanguages: "(en)")
        exactLabel("selfConfiguration.status", "No appearance change has been requested.")
        choose("settings.language", option: "简体中文")
        exactLabel("settings.language.resolved", "当前界面：简体中文")
        exactLabel("selfConfiguration.status", "尚未提出外观调整请求。")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable)
        back.tap()
        navigateMikaSection("chat", in: app)
        let menu = app.buttons["chat.menu"]
        XCTAssertEqual(menu.label, "菜单")
        menu.tap()
        XCTAssertEqual(app.buttons["drawer.close"].label, "关闭菜单")
        XCTAssertEqual(app.buttons["navigation.settings"].label, "设置")
        app.buttons["drawer.close"].tap()
        app.terminate(); launch(systemLanguages: "(zh-Hant)")
        exactLabel("selfConfiguration.status", "尚未提出外观调整请求。")
        choose("settings.language", option: "跟随系统")
        exactLabel("settings.language.resolved", "目前介面：繁體中文")
        exactLabel("selfConfiguration.status", "尚未提出外觀調整要求。")
    }

    func testUnsupportedSystemLanguageUsesTraditionalChineseFallback() {
        launch(systemLanguages: "(fr-FR)")
        exactLabel("selfConfiguration.status", "尚未提出外觀調整要求。")
        exactLabel("settings.language.resolved", "目前介面：繁體中文")
        let permission = app.switches["selfConfiguration.permission"]
        revealLearningElement(permission, in: app)
        XCTAssertEqual(permission.value as? String, "0")
        XCTAssertFalse(app.buttons["selfConfiguration.start"].exists)
    }

    func testChatHeaderAndArchiveBoundaryInEverySupportedLanguage() {
        let cases: [(String, String, String, String)] = [
            ("(zh-Hant)", "尚未設定模型", "請先到設定填寫模型服務與 API Key。", "已完成的問答會加密保存在此裝置"),
            ("(zh-Hans)", "尚未设置模型", "请先到设置填写模型服务与 API Key。", "已完成的问答会加密保存在此设备"),
            ("(en)", "Model not configured", "Set up a model service and API key in Settings first.", "Completed exchanges are encrypted on this device"),
            ("(fr-FR)", "尚未設定模型", "請先到設定填寫模型服務與 API Key。", "已完成的問答會加密保存在此裝置")
        ]
        for (systemLanguages, status, hint, boundary) in cases {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                                   "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
            app.launchEnvironment = [:]
            app.launch()
            let headerStatus = app.staticTexts["chat.status"].firstMatch
            XCTAssertTrue(headerStatus.waitForExistence(timeout: 15))
            XCTAssertEqual(headerStatus.label, status)
            let transcript = app.scrollViews["chat.transcript"].firstMatch
            XCTAssertTrue(transcript.waitForExistence(timeout: 10))
            XCTAssertLessThan(headerStatus.frame.midY, transcript.frame.minY, "Status belongs in the navigation header")
            XCTAssertEqual(app.staticTexts["chat.explanation"].firstMatch.label, hint)
            XCTAssertFalse(app.buttons["chat.archive"].exists)
            XCTAssertFalse(app.staticTexts["chat.historyNotice"].exists)
            let menu = app.buttons["chat.menu"].firstMatch
            XCTAssertTrue(menu.isHittable); menu.tap()
            let history = app.buttons["drawer.archive"].firstMatch
            XCTAssertTrue(history.waitForExistence(timeout: 10)); XCTAssertTrue(history.isEnabled); history.tap()
            let notice = app.staticTexts["archive.boundary"].firstMatch
            XCTAssertTrue(notice.waitForExistence(timeout: 10)); XCTAssertTrue(notice.label.contains(boundary))
            app.buttons["archive.close"].tap()
        }
    }

    func testAdvancedSettingsAndMCPNavigationInEverySupportedLanguage() {
        let cases: [(String, String, String, String)] = [
            ("(zh-Hant)", "設定", "進階與其他", "MCP 伺服器"),
            ("(zh-Hans)", "设置", "高级与其他", "MCP 服务器"),
            ("(en)", "Settings", "Advanced and other", "MCP servers")
        ]
        for (systemLanguages, settingsTitle, advancedTitle, mcpTitle) in cases {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                                   "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
            app.launchEnvironment = [:]
            app.launch()
            navigateMikaSection("settings", in: app)
            XCTAssertTrue(app.navigationBars[settingsTitle].waitForExistence(timeout: 10))
            let advanced = app.buttons["settings.advanced"]
            revealLearningElement(advanced, in: app)
            XCTAssertTrue(advanced.isHittable && advanced.label.contains(advancedTitle))
            advanced.tap()
            let advancedBar = app.navigationBars[advancedTitle]
            XCTAssertTrue(advancedBar.waitForExistence(timeout: 10))
            let mcp = app.buttons["settings.mcpJump"]
            revealLearningElement(mcp, in: app)
            XCTAssertTrue(mcp.isHittable && mcp.label.contains(mcpTitle))
            mcp.tap()
            let mcpBar = app.navigationBars[mcpTitle]
            XCTAssertTrue(mcpBar.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["mcp.status"].waitForExistence(timeout: 10))
            XCTAssertTrue(mcpBar.buttons.firstMatch.isHittable)
            mcpBar.buttons.firstMatch.tap()
            XCTAssertTrue(advancedBar.waitForExistence(timeout: 10))
            XCTAssertTrue(advancedBar.buttons.firstMatch.isHittable)
            advancedBar.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars[settingsTitle].waitForExistence(timeout: 10))
        }
    }

    func testMemoryWebsiteDataNavigationInEverySupportedLanguage() {
        let cases: [(String, String, String, String, String)] = [
            ("(zh-Hant)", "網站登入", "不一定已登入", "不代表目前已登入", "關閉"),
            ("(zh-Hans)", "网站登录", "不一定已登录", "不代表当前已登录", "关闭"),
            ("(en)", "Website logins", "not necessarily signed in", "does not mean you are currently signed in", "Close")
        ]
        for (systemLanguages, title, entryHelp, siteHelp, closeTitle) in cases {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                                   "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
            app.launchEnvironment = [:]
            app.launch()
            navigateMikaSection("memory", in: app)
            let entry = app.buttons["memory.manageWebsites"].firstMatch
            revealLearningElement(entry, in: app)
            XCTAssertEqual(entry.label, title)
            let help = app.staticTexts["memory.browserPending"].firstMatch
            revealLearningElement(help, in: app, visibility: .readableText)
            XCTAssertTrue(help.label.contains(entryHelp))
            revealLearningElement(entry, in: app); entry.tap()
            let detail = app.staticTexts["browser.sites.help"].firstMatch
            XCTAssertTrue(detail.waitForExistence(timeout: 10))
            XCTAssertTrue(detail.label.contains(siteHelp))
            let close = app.buttons["browser.library.close"].firstMatch
            XCTAssertEqual(close.label, closeTitle)
            XCTAssertTrue(app.staticTexts["browser.sites.empty"].waitForExistence(timeout: 20))
            close.tap()
            XCTAssertTrue(app.staticTexts["memory.status"].waitForExistence(timeout: 10))
        }
    }

    private func launch(systemLanguages: String) {
        app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        app.launchEnvironment = [:]; app.launch()
        navigateMikaSection("settings", in: app)
        let appearance = app.buttons["settings.appearance"]
        revealLearningElement(appearance, in: app); appearance.tap()
    }

    private func choose(_ identifier: String, option: String) {
        let picker = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        revealLearningElement(picker, in: app); picker.tap()
        let button = app.buttons[option].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }

    private func exactLabel(_ identifier: String, _ expected: String) {
        let element = app.staticTexts[identifier]
        revealLearningElement(element, in: app)
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 5), .completed)
    }
}
