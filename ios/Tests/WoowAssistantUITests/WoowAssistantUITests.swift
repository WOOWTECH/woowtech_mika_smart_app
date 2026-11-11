import XCTest

// These tests always use the DEBUG fixture, never provider credentials or the network.
final class WoowAssistantUITests: XCTestCase {
    private let sections = ["chat", "browser", "tools", "memory", "settings"]
    private let namespace = UUID().uuidString
    private let fixtureURL = "https://model.example.invalid/v1"
    private var capturedSections = Set<String>()

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        capturedSections.removeAll()
    }

    override func tearDownWithError() throws {
        if let testRun = testRun, testRun.failureCount > 0 {
            attachScreenshot("failure", in: XCUIApplication())
        }
        XCUIApplication().terminate()
    }

    /// Real iPad navigation audit. A fresh UUID and no reset flag keep all
    /// encrypted records, defaults and Keychain items separate from personal data.
    func testRealIPadReadOnlyNavigationAudit() throws {
        executionTimeAllowance = 300
        let app = launchApp(resetStorage: false)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        try XCTSkipUnless(window.frame.width > 600, "Requires the native iPad layout")
        XCTAssertTrue(app.buttons["chat.menu"].isHittable)

        app.buttons["chat.menu"].tap()
        XCTAssertTrue(app.buttons["drawer.close"].waitForExistence(timeout: 10))
        for route in ["chat", "memory", "tools", "browser", "settings"] {
            XCTAssertTrue(app.buttons["navigation.\(route)"].isHittable)
        }
        attachScreenshot("01-drawer", in: app)
        app.buttons["drawer.close"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))

        openSection("settings", in: app)
        openModelSettings(in: app)
        XCTAssertTrue(app.textFields["settings.model"].exists)
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].exists)
        attachScreenshot("02-settings-model", in: app)
        returnFromModelSettings(in: app)
        attachScreenshot("03-settings-return-from-model", in: app)
        for (linkID, title, detailID, name) in [
            ("settings.appearance", "語言與外觀", "selfConfiguration.permission", "04-settings-appearance"),
            ("settings.notifications", "任務通知", "notifications.enabled", "05-settings-notifications")
        ] {
            let link = app.buttons[linkID]
            XCTAssertTrue(link.isHittable)
            link.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: detailID).firstMatch.waitForExistence(timeout: 10))
            attachScreenshot(name, in: app)
            let back = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
        }
        XCTAssertTrue(app.buttons["section.back"].isHittable)
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))

        openSection("memory", in: app)
        XCTAssertTrue(app.staticTexts["memory.empty"].waitForExistence(timeout: 10))
        attachScreenshot("06-memory-memories", in: app)
        app.buttons["memory.segment.skills"].tap()
        XCTAssertTrue(app.staticTexts["skills.empty"].waitForExistence(timeout: 10))
        attachScreenshot("07-memory-skills", in: app)
        app.buttons["memory.segment.pending"].tap()
        XCTAssertTrue(app.staticTexts["memory.pending.empty"].waitForExistence(timeout: 10))
        attachScreenshot("08-memory-pending", in: app)
        app.buttons["memory.segment.memories"].tap()
        XCTAssertTrue(app.staticTexts["memory.empty"].waitForExistence(timeout: 10))
        // This link is a navigation action only; no browsing or data mutation.
        let websiteLink = app.buttons["memory.manageWebsites"]
        for _ in 0..<6 where !websiteLink.isHittable { app.swipeUp() }
        XCTAssertTrue(websiteLink.isHittable)
        websiteLink.tap()
        XCTAssertTrue(app.staticTexts["browser.status"].waitForExistence(timeout: 10))
        attachScreenshot("09-browser-from-memory", in: app)
        XCTAssertEqual(app.buttons["section.back"].label, "返回記憶")
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.staticTexts["memory.status"].waitForExistence(timeout: 10))
        attachScreenshot("10-memory-return-from-browser", in: app)
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))

        openSection("browser", in: app)
        XCTAssertTrue(app.textFields["browser.address"].waitForExistence(timeout: 10))
        let library = app.buttons["browser.library"]
        XCTAssertTrue(library.isHittable)
        library.tap()
        XCTAssertTrue(app.buttons["browser.library.close"].waitForExistence(timeout: 10))
        attachScreenshot("11-browser-library", in: app)
        app.buttons["browser.library.close"].tap()
        XCTAssertTrue(app.staticTexts["browser.status"].waitForExistence(timeout: 10))
        attachScreenshot("12-browser-return-from-library", in: app)
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))

        openSection("tools", in: app)
        XCTAssertTrue(app.staticTexts["mcp.status"].waitForExistence(timeout: 10))
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))
        attachScreenshot("13-chat-after-all-returns", in: app)
    }

    func testEverySectionIsReachableAndPhoneControlIsExcluded() {
        let app = launchApp()
        let excluded = NSPredicate(format: "label MATCHES[c] %@", ".*(手機操作|手機控制|App 操作|螢幕錄影|無障礙控制|ADB|USB helper).*")
        for section in sections {
            openSection(section, in: app)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigation.")).firstMatch.exists,
                           "Routes belong to the drawer, not a persistent bottom bar.")
            if section == "chat" { XCTAssertTrue(app.buttons["chat.menu"].exists) }
            else { XCTAssertTrue(app.buttons["section.back"].exists) }
            XCTAssertEqual(app.descendants(matching: .any).matching(excluded).count, 0)
        }
        openSection("chat", in: app)
        XCTAssertEqual(app.buttons["chat.menu"].label, "選單")
        XCTAssertEqual(app.buttons["chat.newConversation"].label, "新對話")
        app.buttons["chat.menu"].tap()
        XCTAssertEqual(app.buttons["drawer.close"].label, "關閉選單")
        for section in sections { XCTAssertTrue(app.buttons["navigation.\(section)"].exists) }
        app.buttons["drawer.close"].tap()
        openSection("chat", in: app)
    }

    func testSettingsDetailsUseNativeBackBeforeLeavingSettings() {
        let app = launchApp()
        openSection("settings", in: app)
        openModelSettings(in: app)
        returnFromModelSettings(in: app)

        for (linkID, title, detailID) in [
            ("settings.appearance", "語言與外觀", "selfConfiguration.permission"),
            ("settings.notifications", "任務通知", "notifications.enabled")
        ] {
            let link = app.buttons[linkID]
            revealSettings(link, in: app)
            link.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: detailID).firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["section.back"].isHittable,
                           "Root back must not cover the native detail Back button.")
            let nativeBack = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
            waitUntilHittable(nativeBack)
            nativeBack.tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["settings.modelJump"].exists)
        }
        XCTAssertTrue(app.buttons["section.back"].isHittable)
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))
    }

    func testSettingsMemoryAndMCPEntriesOpenExistingScreensAndKeepDrawerRoutes() {
        let app = launchApp()
        openSection("settings", in: app)
        for (linkID, title, destinationID) in [
            ("settings.memoryJump", "記憶與資料", "memory.segment.memories"),
            ("settings.mcpJump", "MCP 伺服器", "mcp.status")
        ] {
            let link = app.buttons[linkID]
            revealSettings(link, in: app)
            link.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: destinationID).firstMatch.waitForExistence(timeout: 10),
                          "The settings row must open the existing working destination.")
            XCTAssertFalse(app.buttons["section.back"].isHittable,
                           "The root back button must not cover the native detail Back button.")
            let nativeBack = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
            waitUntilHittable(nativeBack)
            nativeBack.tap()
            XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons[linkID].exists)
        }
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))
        app.buttons["chat.menu"].tap()
        XCTAssertTrue(app.buttons["navigation.memory"].exists)
        XCTAssertTrue(app.buttons["navigation.tools"].exists)
    }

    func testUnconfiguredSendIsDisabledAndDraftSurvivesNavigation() {
        let app = launchApp()
        XCTAssertEqual(app.staticTexts["chat.status"].label, "尚未設定模型")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        let draft = chatDraftControl(in: app)
        waitUntilHittable(draft)
        draft.tap()
        draft.typeText("Keep this draft 42")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        // Opening the drawer resigns the keyboard while retaining the draft.
        openSection("browser", in: app)
        openSection("settings", in: app)
        openSection("chat", in: app)
        assertDraft("Keep this draft 42", in: app)
        let restoredDraft = chatDraftControl(in: app)
        restoredDraft.tap()
        restoredDraft.typeText("\nSecond line")
        assertDraft("Keep this draft 42\nSecond line", in: app)
        app.buttons["chat.dismissKeyboard"].tap()
        assertDraft("Keep this draft 42\nSecond line", in: app)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        attachScreenshot("unconfigured-draft-retained", in: app)
    }

    func testComposerGrowsThenScrollsAtFiveLinesAndPDFSheetKeepsDraft() {
        let app = launchApp()
        let draft = chatDraftControl(in: app)
        waitUntilHittable(draft)
        draft.tap()
        draft.typeText("A")
        XCTAssertEqual(draft.value as? String, "A")
        let oneLineHeight = draft.frame.height
        var expected = "A"
        for line in ["B", "C", "D", "E"] {
            draft.typeText("\n" + line)
            expected += "\n" + line
            XCTAssertEqual(draft.value as? String, expected,
                           "Return must insert a draft line, not send or discard it.")
        }
        let fiveLineHeight = draft.frame.height
        XCTAssertGreaterThan(fiveLineHeight, oneLineHeight + 10)
        draft.typeText("\nF")
        expected += "\nF"
        XCTAssertEqual(draft.value as? String, expected)
        XCTAssertLessThanOrEqual(draft.frame.height, fiveLineHeight + 4,
                                 "The sixth line should scroll inside the composer.")

        let attach = app.buttons["chat.pdf.open"]
        let send = app.buttons["chat.send"]
        for control in [draft, attach, send] {
            XCTAssertFalse(control.frame.isEmpty)
            XCTAssertLessThanOrEqual(control.frame.maxY, mikaUnobscuredBottom(in: app),
                                     "Composer controls must remain above the keyboard on a compact iPhone.")
        }
        XCTAssertTrue(attach.isHittable)
        XCTAssertFalse(send.isEnabled, "Typing does not bypass missing model configuration.")
        let done = app.buttons["chat.dismissKeyboard"]
        waitUntilHittable(done)
        done.tap()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 10), .completed)
        XCTAssertEqual(draft.value as? String, expected)

        waitUntilHittable(attach)
        attach.tap()
        let closePDF = app.buttons["chat.pdf.done"]
        XCTAssertTrue(closePDF.waitForExistence(timeout: 5))
        closePDF.tap()
        XCTAssertEqual(chatDraftControl(in: app).value as? String, expected)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
    }

    func testBrowserReportsCurrentLimitationsAndToolsIsReachable() {
        let app = launchApp()
        openSection("browser", in: app)
        XCTAssertEqual(app.staticTexts["browser.status"].label, "輸入網址開始瀏覽")
        XCTAssertTrue(app.textFields["browser.address"].exists)
        XCTAssertTrue(app.buttons["browser.open"].isEnabled)
        XCTAssertFalse(app.buttons["browser.research"].isEnabled)
        XCTAssertEqual(app.staticTexts["browser.explanation"].label,
                       "可手動登入網站及選取上傳檔案；網站資料保留於此 App。模型研究與每次核准的操作各自受限。")
        XCTAssertFalse(app.staticTexts["公開 HTTPS 頁面已通過第一層安全政策"].exists)
        XCTAssertFalse(app.staticTexts["browser.answer"].exists)
        XCTAssertFalse(app.staticTexts["browser.learning"].exists)
        openSection("tools", in: app)
        XCTAssertTrue(app.buttons["section.back"].exists)
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "尚未設定 MCP")
        XCTAssertTrue(app.staticTexts["mcp.testIsolation"].exists)
        for _ in 0..<4 where !app.buttons["mcp.connect"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["mcp.connect"].exists)
        XCTAssertFalse(app.buttons["mcp.connect"].isEnabled)
    }

    func testHTTPSValidationThenConfiguredChatWithoutAutomaticHistoryRestore() {
        let app = launchApp()
        fillConfiguration(in: app, baseURL: "http://model.example.invalid/v1")
        save(in: app)
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.error"].label.contains("HTTPS"))
        XCTAssertEqual(app.staticTexts["settings.keyStatus"].label, "尚未儲存金鑰。")
        replaceBaseURL(fixtureURL, in: app)
        save(in: app)
        assertSaved(in: app)
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        send("Hello fixture 17", in: app)
        assertReply("測試回覆：Hello fixture 17", in: app)
        XCTAssertTrue(app.staticTexts["chat.historyNotice"].label.contains("加密保存在此裝置"))
        assertDraft("", in: app)
        attachScreenshot("fixture-reply", in: app)

        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        XCTAssertEqual(relaunched.staticTexts["chat.status"].label, "模型已設定")
        XCTAssertFalse(relaunched.staticTexts["chat.message.1.assistant"].exists)
        assertDraft("", in: relaunched)
    }

    func testStoredKeyCanBeReusedButNotForDifferentHost() {
        let app = launchApp()
        configure(in: app)
        // An empty SecureField reuses the existing Keychain item.
        save(in: app)
        assertSaved(in: app)
        replaceBaseURL("https://other.example.invalid/v1", in: app)
        save(in: app)
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.error"].label.contains("重新輸入"))
        returnFromModelSettings(in: app)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        openSection("settings", in: relaunched)
        openModelSettings(in: relaunched)
        XCTAssertEqual(relaunched.textFields["settings.baseURL"].value as? String, fixtureURL)
        XCTAssertTrue(relaunched.staticTexts["settings.keyStatus"].label.contains("已儲存金鑰"))
        returnFromModelSettings(in: relaunched)
    }

    func testCancellationPreservesDraftAndAllowsAnotherAttempt() {
        let app = launchApp()
        configure(in: app)
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        send("[fixture:wait]", in: app)
        let cancel = app.buttons["chat.cancel"]
        waitUntilHittable(cancel)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["chat.notice"].waitForExistence(timeout: 5))
        assertDraft("[fixture:wait]", in: app)
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        XCTAssertTrue(chatDraftControl(in: app).isEnabled)
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        attachScreenshot("cancel-draft-retained", in: app)
    }

    func testFailureRetainsDraftAndRetryProducesReply() {
        let app = launchApp()
        configure(in: app)
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        send("[fixture:error-once]", in: app)
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 5))
        assertDraft("[fixture:error-once]", in: app)
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        attachScreenshot("error-draft-retained", in: app)
        app.buttons["chat.send"].tap()
        assertReply("測試回覆：[fixture:error-once]", in: app)
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
        assertDraft("", in: app)
    }

    func testKeychainWriteFailureDoesNotPublishConfiguration() {
        let app = launchApp(keychainWriteFails: true)
        fillConfiguration(in: app)
        save(in: app)
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.error"].label.contains("Keychain"))
        returnFromModelSettings(in: app)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        XCTAssertEqual(relaunched.staticTexts["chat.status"].label, "尚未設定模型")
        XCTAssertFalse(relaunched.buttons["chat.send"].isEnabled)
    }

    func testRemovingConfigurationKeepsDraftAndDisablesSending() {
        let app = launchApp()
        enterChatDraft("Draft after key removal", in: app)
        configure(in: app)
        let remove = app.buttons["settings.remove"]
        revealSettings(remove, in: app)
        remove.tap()
        XCTAssertTrue(app.staticTexts["settings.notice"].label.contains("已移除"))
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        assertDraft("Draft after key removal", in: app)
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        XCTAssertEqual(relaunched.staticTexts["chat.status"].label, "尚未設定模型")
    }

    func testMCPEndpointValidationAndKeychainPersistenceWithoutNetworking() {
        let app = launchApp()
        openSection("tools", in: app)
        let endpoint = app.secureTextFields["mcp.endpoint"]
        revealMCP(endpoint, in: app)
        enter("http://mcp.example.invalid/private", into: endpoint)
        revealMCP(app.buttons["mcp.save"], in: app)
        app.buttons["mcp.save"].tap()
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "尚未設定 MCP")
        revealMCP(app.staticTexts["mcp.error"], in: app)
        XCTAssertTrue(app.staticTexts["mcp.error"].label.contains("HTTPS"))
        revealMCP(app.buttons["mcp.clearDraft"], in: app, upward: false)
        app.buttons["mcp.clearDraft"].tap()
        revealMCP(endpoint, in: app, upward: false)
        enter("https://mcp.example.invalid/fixture-private", into: endpoint)
        revealMCP(app.buttons["mcp.save"], in: app)
        app.buttons["mcp.save"].tap()
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "端點已儲存，尚未驗證連線")
        XCTAssertFalse(app.buttons["mcp.clearDraft"].isEnabled)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        openSection("tools", in: relaunched)
        XCTAssertEqual(relaunched.staticTexts["mcp.status"].label, "端點已儲存，尚未驗證連線")
        XCTAssertTrue(relaunched.staticTexts["mcp.testIsolation"].exists)
        revealMCP(relaunched.buttons["mcp.connect"], in: relaunched)
        XCTAssertFalse(relaunched.buttons["mcp.connect"].isEnabled)
    }

    func testMCPKeychainWriteFailureIsNotReportedAsSaved() {
        let app = launchApp(keychainWriteFails: true)
        openSection("tools", in: app)
        let endpoint = app.secureTextFields["mcp.endpoint"]
        revealMCP(endpoint, in: app)
        enter("https://mcp.example.invalid/fixture-private", into: endpoint)
        revealMCP(app.buttons["mcp.save"], in: app)
        app.buttons["mcp.save"].tap()
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "尚未設定 MCP")
        revealMCP(app.staticTexts["mcp.error"], in: app)
        XCTAssertTrue(app.staticTexts["mcp.error"].label.contains("Keychain"))
    }

    func testMCPRemovalClearsOnlyItsSavedEndpoint() {
        let app = launchApp()
        configure(in: app)
        returnFromModelSettings(in: app)
        openSection("tools", in: app)
        let endpoint = app.secureTextFields["mcp.endpoint"]
        revealMCP(endpoint, in: app)
        enter("https://mcp.example.invalid/fixture-private", into: endpoint)
        revealMCP(app.buttons["mcp.save"], in: app)
        app.buttons["mcp.save"].tap()
        XCTAssertEqual(app.staticTexts["mcp.status"].label, "端點已儲存，尚未驗證連線")
        revealMCP(app.buttons["mcp.remove"], in: app)
        app.buttons["mcp.remove"].tap()
        // iOS 26 exposes the confirmation row before its nested action button.
        // firstMatch can tap the wrapper; use the last exact identifier/label
        // match (the single action on older iOS), without coordinate taps.
        let confirmations = app.buttons.matching(identifier: "mcp.confirmRemove")
            .matching(NSPredicate(format: "label == %@", "移除端點"))
        XCTAssertTrue(confirmations.firstMatch.waitForExistence(timeout: 5))
        guard let confirm = confirmations.allElementsBoundByIndex.last else {
            XCTFail("The MCP endpoint removal confirmation is missing.")
            return
        }
        waitUntilHittable(confirm)
        confirm.tap()
        let status = app.staticTexts["mcp.status"]
        let removed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", "尚未設定 MCP"),
            object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        XCTAssertEqual(status.label, "尚未設定 MCP")
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        XCTAssertEqual(relaunched.staticTexts["chat.status"].label, "模型已設定")
        openSection("tools", in: relaunched)
        XCTAssertEqual(relaunched.staticTexts["mcp.status"].label, "尚未設定 MCP")
    }

    private func revealMCP(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<5 where !element.isHittable {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        waitUntilHittable(element)
    }

    private func launchApp(resetStorage: Bool = true, keychainWriteFails: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode", "-UITestNamespace", namespace]
        if resetStorage { app.launchArguments.append("-UITestResetStorage") }
        if keychainWriteFails { app.launchArguments.append("-UITestKeychainWriteFailure") }
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["uitest.banner"].exists)
        attachScreenshot("launch", in: app)
        return app
    }

    private func fillConfiguration(in app: XCUIApplication, baseURL: String? = nil) {
        openSection("settings", in: app)
        openModelSettings(in: app)
        enter(baseURL ?? fixtureURL, into: app.textFields["settings.baseURL"])
        let model = app.textFields["settings.model"]
        revealSettings(model, in: app)
        enter("ui-test-model", into: model)
        let key = app.secureTextFields["settings.apiKey"]
        revealSettings(key, in: app)
        enter("fixture-only-not-a-real-key", into: key)
    }

    private func configure(in app: XCUIApplication) {
        fillConfiguration(in: app)
        save(in: app)
        assertSaved(in: app)
    }

    private func save(in app: XCUIApplication) {
        let save = app.buttons["settings.save"]
        revealSettings(save, in: app)
        save.tap()
    }

    private func assertSaved(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["settings.notice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.notice"].label.contains("尚未驗證連線"))
        XCTAssertFalse(app.staticTexts["settings.error"].exists)
    }

    private func replaceBaseURL(_ value: String, in app: XCUIApplication) {
        let clear = app.buttons["settings.clearBaseURL"]
        revealSettings(clear, in: app, upward: false)
        clear.tap()
        enter(value, into: app.textFields["settings.baseURL"])
    }

    private func enter(_ text: String, into field: XCUIElement) {
        waitUntilHittable(field)
        field.tap()
        field.typeText(text + "\n")
    }

    private func enterChatDraft(_ text: String, in app: XCUIApplication) {
        let field = chatDraftControl(in: app)
        waitUntilHittable(field)
        field.tap()
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        let done = app.buttons["chat.dismissKeyboard"]
        waitUntilHittable(done)
        done.tap()
    }

    private func send(_ text: String, in app: XCUIApplication) {
        enterChatDraft(text, in: app)
        let send = app.buttons["chat.send"]
        waitUntilHittable(send)
        XCTAssertTrue(send.isEnabled)
        send.tap()
    }

    private func assertReply(_ expected: String, in app: XCUIApplication) {
        let reply = app.staticTexts["chat.message.1.assistant"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        XCTAssertEqual(reply.label, expected)
    }

    private func revealSettings(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<3 where !element.isHittable {
            if upward { app.scrollViews.firstMatch.swipeUp() }
            else { app.scrollViews.firstMatch.swipeDown() }
        }
        waitUntilHittable(element)
    }

    private func openSection(_ section: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        navigateMikaSection(section, in: app, file: file, line: line)
        XCTAssertTrue(app.staticTexts["\(section).status"].waitForExistence(timeout: 5), file: file, line: line)
        if capturedSections.insert(section).inserted { attachScreenshot("section-\(section)", in: app) }
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntilHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, file: file, line: line)
    }

    private func assertDraft(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = chatDraftControl(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        let expectedValue = expected.isEmpty ? "輸入訊息" : expected
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR value == %@", expected, expectedValue), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, file: file, line: line)
    }
}
