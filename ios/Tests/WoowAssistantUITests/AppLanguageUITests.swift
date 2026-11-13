import XCTest

/// Reuse the isolated, already configured synthetic streaming namespace while
/// changing only the actual preferred UI language between launches.
func launchLocalizedStreamingFixture(_ app: XCUIApplication, systemLanguages: String, namespace: String) {
    app.terminate()
    app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                           "-UITestMode", "-UITestNamespace", namespace, "-UITestChatStreaming"]
    app.launchEnvironment = [:]
    app.launch()
}

/// Actual settings UI acceptance. Never sets defaults/bindings or overrides a
/// product DEBUG locale. Each case owns fresh storage; model requests stay off.
final class AppLanguageUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    func testExplicitEnglishPersistsAndKeepsTheAppearanceChoice() {
        launch(systemLanguages: "(zh-Hant)")
        choose("selfConfiguration.appearance.dark")
        choose("settings.language.en")
        XCTAssertTrue(app.navigationBars["Language and appearance"].waitForExistence(timeout: 5))
        assertSelected("selfConfiguration.appearance.dark")
        app.terminate(); launch(systemLanguages: "(zh-Hant)")
        XCTAssertTrue(app.navigationBars["Language and appearance"].waitForExistence(timeout: 10))
        assertSelected("settings.language.en")
        assertSelected("selfConfiguration.appearance.dark")
    }

    func testPlayLanguageChoicesAndSystemFollowActualPreferredLanguages() {
        launch(systemLanguages: "(en)")
        XCTAssertTrue(app.navigationBars["Language and appearance"].waitForExistence(timeout: 10))
        assertSelected("settings.language.system")
        // As on Play: follow the system, 繁體中文 or English; 简体中文 is not offered.
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "settings.language."))
        XCTAssertEqual(choices.count, 3)
        XCTAssertFalse(app.buttons["settings.language.zh-Hans"].exists)
        choose("settings.language.zh-Hant")
        XCTAssertTrue(app.navigationBars["語言與外觀"].waitForExistence(timeout: 5))
        app.terminate(); launch(systemLanguages: "(en)")
        XCTAssertTrue(app.navigationBars["語言與外觀"].waitForExistence(timeout: 10))
        assertSelected("settings.language.zh-Hant")
        choose("settings.language.system")
        XCTAssertTrue(app.navigationBars["Language and appearance"].waitForExistence(timeout: 5))
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable)
        back.tap()
        navigateMikaSection("chat", in: app)
        XCTAssertEqual(app.buttons["chat.menu"].label, "Menu")
    }

    func testUnsupportedSystemLanguageUsesTraditionalChineseFallback() {
        launch(systemLanguages: "(fr-FR)")
        XCTAssertTrue(app.navigationBars["語言與外觀"].waitForExistence(timeout: 10))
        assertSelected("settings.language.system")
        // The page has Play's two lists only: no model permission to change the appearance.
        XCTAssertFalse(app.switches["selfConfiguration.permission"].exists)
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

    /// Offline fixture: every example replaces the draft but never sends it.
    func testStoreExamplesFillDraftInEveryLanguageWithoutSending() {
        let cases: [(String, [String])] = [
            ("(zh-Hant)", ["幫我寫一則友善的訊息回覆", "幫我摘要附上的文件，列出重點", "在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較", "在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點", "記住我偏好使用繁體中文，回答簡短一點", "你記得我有哪些偏好？"]),
            ("(zh-Hans)", ["帮我写一则友善的消息回复", "帮我摘要附上的文件，列出重点", "在 104 人力银行搜索台北的 AI 产品经理职位，选五个帮我比较", "在 momo 购物找 1,000 元以内、4.5 星以上的无线耳机，比较三款的优缺点", "记住我偏好使用繁体中文，回答简短一点", "你记得我有哪些偏好？"]),
            ("(en)", ["Help me write a friendly reply to this message.", "Summarize the document I attach and list its key points.", "Search 104 Job Bank for AI product manager jobs in Taipei and compare five of them for me.", "Find three wireless earbuds under NT$1,000 rated 4.5 stars or more on momo and compare their pros and cons.", "Remember that I prefer concise answers in Traditional Chinese.", "What preferences have I told you to remember?"])
        ]
        let identifiers = ["reply", "document", "web", "shopping", "remember", "recall"]
        for (systemLanguages, expected) in cases {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                                   "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
            app.launchEnvironment = [:]
            app.launch()
            let draft = chatDraftControl(in: app)
            XCTAssertTrue(draft.waitForExistence(timeout: 15))
            for (id, text) in zip(identifiers, expected) {
                let button = app.buttons["chat.emptyExample." + id]
                revealLearningElement(button, in: app)
                XCTAssertTrue(button.isHittable, id)
                XCTAssertEqual(button.label, text)
                button.tap()
                let value = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: draft)
                XCTAssertEqual(XCTWaiter.wait(for: [value], timeout: 5), .completed, id)
                XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
                // An example only fills the draft; nothing is sent. Like Android, the
                // send key is then ready and a tap explains the missing model.
                XCTAssertTrue(app.buttons["chat.send"].isEnabled)
            }
        }
    }

    func testAboutHeroAndDiagnosticsInEverySupportedLanguage() {
        let cases: [(String, String, String, String)] = [
            ("(zh-Hant)", "關於渥屋助理", "在同一個地方對話、瀏覽網頁，並記住有用的資訊", "診斷資訊"),
            ("(zh-Hans)", "关于渥屋助理", "在同一个地方对话、浏览网页，并记住有用的信息", "诊断信息"),
            ("(en)", "About woowtech agent", "Chat, browse, and keep useful information in one place", "Diagnostics")
        ]
        for (systemLanguages, aboutTitle, tagline, diagnosticsTitle) in cases {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                                   "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
            app.launchEnvironment = [:]
            app.launch()
            navigateMikaSection("settings", in: app)
            let about = app.buttons["settings.about"]
            revealLearningElement(about, in: app)
            XCTAssertTrue(about.isHittable); about.tap()
            XCTAssertTrue(app.navigationBars[aboutTitle].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["settings.about.tagline"].label, tagline)
            XCTAssertTrue(app.staticTexts["settings.about.version"].exists)
            XCTAssertTrue(app.staticTexts["settings.about.build"].exists)
            let feedback = app.buttons["settings.about.feedback"]
            revealLearningElement(feedback, in: app)
            XCTAssertTrue(feedback.isHittable); feedback.tap()
            let diagnostics = app.buttons["settings.about.diagnostics"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                                  object: diagnostics)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed); diagnostics.tap()
            XCTAssertTrue(app.navigationBars[diagnosticsTitle].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["settings.about.diagnostics.report"].exists)
        }
    }

    func testAdvancedSettingsAndMCPNavigationInEverySupportedLanguage() {
        let cases: [(String, String, String, String)] = [
            ("(zh-Hant)", "設定", "進階與其他", "MCP 伺服器"),
            ("(zh-Hans)", "设置", "高级与其他", "MCP 服务器"),
            ("(en)", "Settings", "Advanced & other", "MCP servers")
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
            ("(en)", "Website sign-ins", "not necessarily signed in", "does not mean you are currently signed in", "Close")
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

    /// Tap one row of a single-choice list; the row reports itself selected.
    private func choose(_ identifier: String) {
        let row = app.buttons[identifier]
        revealLearningElement(row, in: app); row.tap()
        assertSelected(identifier)
    }

    private func assertSelected(_ identifier: String) {
        let row = app.buttons[identifier]
        revealLearningElement(row, in: app)
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, identifier)
    }
}
