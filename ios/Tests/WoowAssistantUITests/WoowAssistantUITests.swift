import XCTest
import CoreGraphics

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
            ("settings.appearance", "語言與外觀", "selfConfiguration.appearance.system", "04-settings-appearance"),
            ("settings.notifications", "通知", "notifications.enabled", "05-settings-notifications")
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
        XCTAssertTrue(app.buttons["signIns.close"].waitForExistence(timeout: 10))
        attachScreenshot("09-sign-ins-from-memory", in: app)
        app.buttons["signIns.close"].tap()
        XCTAssertTrue(app.staticTexts["browser.status"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["section.back"].label, "返回記憶")
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.staticTexts["memory.status"].waitForExistence(timeout: 10))
        attachScreenshot("10-memory-return-from-browser", in: app)
        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))

        openSection("browser", in: app)
        XCTAssertTrue(app.textFields["browser.address"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["browser.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["browser.library"].exists, "Like the Play build, favorites and recent pages are on the start page.")
        attachScreenshot("11-browser-start-page", in: app)
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
        // Like Play's drawer: 新對話 takes the place of a Chat row; the rest are routes.
        XCTAssertTrue(app.buttons["drawer.newConversation"].exists)
        for section in sections where section != "chat" { XCTAssertTrue(app.buttons["navigation.\(section)"].exists) }
        app.buttons["drawer.close"].tap()
        openSection("chat", in: app)
    }

    func testSettingsDetailsUseNativeBackBeforeLeavingSettings() {
        let app = launchApp()
        openSection("settings", in: app)
        openModelSettings(in: app)
        returnFromModelSettings(in: app)
        // Task notifications start off, so the row shows Android's 已關閉.
        XCTAssertTrue(app.buttons["settings.notifications"].label.contains("已關閉"))

        for (linkID, title, detailID) in [
            ("settings.appearance", "語言與外觀", "selfConfiguration.appearance.system"),
            ("settings.notifications", "通知", "notifications.enabled")
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

    func testSettingsStatusCardAddsTheMissingModel() {
        let app = launchApp()
        openSection("settings", in: app)
        XCTAssertEqual(app.staticTexts["settings.status"].label, "還沒有能用的模型")
        XCTAssertEqual(app.staticTexts["settings.status.detail"].label, "新增一個支援工具呼叫的模型")
        let fix = app.buttons["settings.status.fix"]
        XCTAssertEqual(fix.label, "新增")
        waitUntilHittable(fix)
        fix.tap()
        XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 10))
        // No provider yet: the add form is open on the Play build's first chip.
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["setup.preset.OpenRouter"].isSelected)
        returnFromModelSettings(in: app)
    }

    /// Android Onboarding.start: with no main model and the setup never
    /// finished, the App opens on the welcome page. 開始設定 shows the model
    /// page in its first-launch mode (providers before the roles), where 下一步
    /// waits for a main model; Back returns to the welcome page.
    func testFirstLaunchWelcomeLeadsToModelSetupWhereNextWaitsForMainModel() {
        let app = XCUIApplication()
        // Without -WoowSkipOnboarding: the first launch people see.
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage"]
        app.launchEnvironment = [:]
        app.launch()
        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["welcome.title"].label, "你好，我是渥屋助理")
        XCTAssertEqual(app.staticTexts["welcome.lead"].label, "在同一個地方對話、語音輸入、瀏覽網頁，並記住有用的資訊。")
        for feature in ["chat", "voice", "web", "memory"] {
            XCTAssertTrue(app.descendants(matching: .any)["welcome.feature." + feature].exists, "Welcome lists \(feature)")
        }
        XCTAssertEqual(app.staticTexts["welcome.note"].label, "先設定自己的模型帳號或 API Key，即可開始使用。")
        XCTAssertEqual(start.label, "開始設定")
        attachScreenshot("onboarding-welcome", in: app)

        waitUntilHittable(start)
        start.tap()
        let bar = app.navigationBars["設定模型"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["setup.lead"].label.hasPrefix("渥屋助理用你自己的模型服務來思考。"))
        let next = app.buttons["setup.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(next.label, "下一步")
        XCTAssertFalse(next.isEnabled, "下一步 waits for a main model.")
        // No provider yet: the add form is open above the main model's role.
        let preset = app.buttons["setup.preset.OpenRouter"]
        let main = app.buttons["models.role.main"]
        XCTAssertTrue(preset.waitForExistence(timeout: 10))
        XCTAssertTrue(main.exists)
        XCTAssertLessThan(preset.frame.minY, main.frame.minY, "Providers come before the roles on first launch.")
        XCTAssertFalse(app.buttons["settings.voice.open"].exists, "Speech to text stays in Settings, as on Play.")
        XCTAssertTrue(app.staticTexts["setup.onboardingNote"].exists)
        attachScreenshot("onboarding-model-setup", in: app)

        let back = bar.buttons.firstMatch
        waitUntilHittable(back)
        back.tap()
        waitUntilHittable(start)
    }

    /// Like Back on Android's welcome page: 稍後再說 shows the chat without
    /// finishing the setup, so the next launch with no main model asks again.
    func testWelcomeNotNowShowsTheChatAndTheNextLaunchAsksAgain() {
        let app = XCUIApplication()
        // Without -WoowSkipOnboarding: the first launch people see.
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage"]
        app.launchEnvironment = [:]
        app.launch()
        let later = app.buttons["welcome.later"]
        XCTAssertTrue(later.waitForExistence(timeout: 15))
        XCTAssertEqual(later.label, "稍後再說")
        waitUntilHittable(later)
        later.tap()
        waitUntilHittable(app.buttons["chat.menu"])
        XCTAssertEqual(app.staticTexts["chat.status"].label, "尚未設定模型")
        XCTAssertTrue(app.staticTexts["uitest.banner"].exists)
        attachScreenshot("onboarding-later-chat", in: app)

        // Same namespace, no reset: still no main model, so it starts again.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-UITestResetStorage" }
        app.launch()
        XCTAssertTrue(app.buttons["welcome.start"].waitForExistence(timeout: 15))
    }

    func testDrawerAboutOpensAndReturnsToChat() {
        let app = launchApp()
        let draft = chatDraftControl(in: app)
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        draft.tap()
        draft.typeText("保留草稿")
        let dismiss = app.buttons["chat.dismissKeyboard"]
        if dismiss.exists { dismiss.tap() }
        app.buttons["chat.menu"].tap()
        let about = app.buttons["navigation.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 10))
        XCTAssertEqual(about.label, "關於渥屋助理")
        about.tap()
        XCTAssertTrue(app.staticTexts["settings.about.appName"].waitForExistence(timeout: 10))
        app.buttons["section.back"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertEqual(draft.value as? String, "保留草稿")
    }

    func testSettingsAboutShowsInstalledVersionAndReturnsToSettings() {
        let app = launchApp()
        openSection("settings", in: app)
        let link = app.buttons["settings.about"]
        revealSettings(link, in: app)
        XCTAssertTrue(link.isEnabled)
        XCTAssertEqual(link.label, "關於渥屋助理")
        let homeVersion = link.value as? String
        link.tap()

        let bar = app.navigationBars["關於渥屋助理"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["settings.about.appName"].label, "渥屋助理")
        XCTAssertEqual(app.staticTexts["settings.about.tagline"].label, "在同一個地方對話、瀏覽網頁，並記住有用的資訊")
        let version = app.staticTexts["settings.about.version"]
        let build = app.staticTexts["settings.about.build"]
        XCTAssertTrue(version.exists && build.exists)
        XCTAssertNotEqual(version.label, "版本資訊不可用")
        XCTAssertFalse(version.label.contains("$("))
        XCTAssertFalse(build.label.contains("$("))
        XCTAssertEqual("版本 " + (homeVersion ?? ""), version.label,
                       "Home and detail show the same installed version")
        XCTAssertTrue(build.label.hasPrefix("· 建置 ") && build.label.count > "· 建置 ".count)
        // The Play edition has no GitHub entries; feedback is diagnostics by email.
        let feedback = app.buttons["settings.about.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 10))
        XCTAssertTrue(feedback.label.contains("回報問題") && feedback.label.contains("woowtech@designsmart.com.tw"))
        for id in ["repository", "guide"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "settings.about." + id).firstMatch.exists,
                           "GitHub entry still shown: \(id)")
        }
        XCTAssertEqual(app.staticTexts["settings.about.dataNote"].label, "你送出的內容由你選擇的 AI 服務商處理。")
        XCTAssertEqual(app.staticTexts["settings.about.copyright"].label,
                       "© 2026 WOOW TECH CO., LTD. · 基於 wangzan101/Mika（Apache-2.0）")
        // Play's About › Released under Apache-2.0 license → Licenses, with the
        // upstream texts; no repository link.
        let license = app.buttons["settings.about.license"]
        for _ in 0..<5 where !license.isHittable { app.scrollViews.firstMatch.swipeUp() }
        waitUntilHittable(license)
        XCTAssertTrue(license.label.contains("Apache-2.0"), license.label)
        license.tap()
        let licenses = app.navigationBars["Apache-2.0 授權條款"]
        XCTAssertTrue(licenses.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["settings.license.text"].waitForExistence(timeout: 10))
        let licensesBack = licenses.buttons.firstMatch
        waitUntilHittable(licensesBack)
        licensesBack.tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["section.back"].isHittable)
        let nativeBack = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
        waitUntilHittable(nativeBack)
        nativeBack.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.about"].exists)
    }

    func testAboutDiagnosticsCanBeReviewedAndCopied() {
        let app = launchApp()
        openSection("settings", in: app)
        let link = app.buttons["settings.about"]
        revealSettings(link, in: app)
        link.tap()
        let feedback = app.buttons["settings.about.feedback"]
        for _ in 0..<5 where !feedback.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(feedback.isHittable)
        feedback.tap()
        let explanation = app.staticTexts["settings.about.feedback.detail"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        XCTAssertEqual(explanation.label, "複製診斷資訊後，寄到 woowtech@designsmart.com.tw")
        let entry = app.buttons["settings.about.diagnostics"]
        waitUntilHittable(entry)
        entry.tap()
        let report = app.staticTexts["settings.about.diagnostics.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        XCTAssertTrue(report.label.contains("App version:"))
        XCTAssertTrue(report.label.contains("iOS/iPadOS:"))
        let copy = app.buttons["settings.about.diagnostics.copy"]
        XCTAssertTrue(app.buttons["settings.about.diagnostics.share"].exists)
        XCTAssertEqual(copy.label, "複製")
        copy.tap()
        XCTAssertEqual(copy.label, "已複製")
        app.navigationBars["診斷資訊"].buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["關於渥屋助理"].waitForExistence(timeout: 10))
    }

    func testSettingsMemoryAndMCPEntriesOpenExistingScreensAndKeepDrawerRoutes() {
        let app = launchApp()
        openSection("settings", in: app)
        let memory = app.buttons["settings.memoryJump"]
        revealSettings(memory, in: app); memory.tap()
        let memoryBar = app.navigationBars["記憶與資料"]
        XCTAssertTrue(memoryBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["memory.segment.memories"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["section.back"].isHittable)
        let memoryBack = memoryBar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
        waitUntilHittable(memoryBack); memoryBack.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))

        let advanced = app.buttons["settings.advanced"]
        revealSettings(advanced, in: app); advanced.tap()
        let advancedBar = app.navigationBars["進階與其他"]
        XCTAssertTrue(advancedBar.waitForExistence(timeout: 10))
        let mcp = app.buttons["settings.mcpJump"]
        revealSettings(mcp, in: app); mcp.tap()
        let mcpBar = app.navigationBars["MCP 伺服器"]
        XCTAssertTrue(mcpBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["mcp.status"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["section.back"].isHittable)
        let mcpBack = mcpBar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
        waitUntilHittable(mcpBack); mcpBack.tap()
        XCTAssertTrue(advancedBar.waitForExistence(timeout: 10))
        XCTAssertTrue(mcp.waitForExistence(timeout: 10))
        let advancedBack = advancedBar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
        waitUntilHittable(advancedBack); advancedBack.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.advanced"].exists)

        app.buttons["section.back"].tap()
        XCTAssertTrue(app.buttons["chat.menu"].waitForExistence(timeout: 10))
        app.buttons["chat.menu"].tap()
        XCTAssertTrue(app.buttons["navigation.memory"].exists)
        XCTAssertTrue(app.buttons["navigation.tools"].exists)
    }

    func testUnconfiguredSendExplainsMissingModelAndDraftSurvivesNavigation() {
        let app = launchApp()
        XCTAssertEqual(app.staticTexts["chat.status"].label, "尚未設定模型")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled, "An empty draft has nothing to send.")
        let draft = chatDraftControl(in: app)
        waitUntilHittable(draft)
        draft.tap()
        draft.typeText("Keep this draft 42")
        assertSendExplainsMissingModel(in: app)
        assertDraft("Keep this draft 42", in: app)
        // The send tap ended editing; resume it so the drawer step below still
        // proves that opening the drawer resigns the keyboard.
        let editing = chatDraftControl(in: app)
        waitUntilHittable(editing)
        editing.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Opening the drawer resigns the keyboard while retaining the draft.
        openSection("browser", in: app)
        openSection("settings", in: app)
        openSection("chat", in: app)
        assertDraft("Keep this draft 42", in: app)
        let restoredDraft = chatDraftControl(in: app)
        waitUntilHittable(restoredDraft)
        XCTAssertFalse(restoredDraft.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(restoredDraft.frame))
        XCTAssertLessThanOrEqual(restoredDraft.frame.maxY, mikaUnobscuredBottom(in: app))
        // A generic AX tap landed the caret before the first character on
        // iOS 18. Tap the field's trailing text area, as a user appending to
        // the retained draft would, then verify the insertion point via value.
        restoredDraft.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        restoredDraft.typeText("\nS")
        assertDraft("Keep this draft 42\nS", in: app)
        restoredDraft.typeText("econd line")
        assertDraft("Keep this draft 42\nSecond line", in: app)
        app.buttons["chat.dismissKeyboard"].tap()
        assertDraft("Keep this draft 42\nSecond line", in: app)
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        attachScreenshot("unconfigured-draft-retained", in: app)
    }

    func testExamplesOnlyReplaceDraftWhenSyntheticModelIsConfigured() {
        let app = launchApp()
        configure(in: app)
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        let cases = [
            ("reply", "幫我寫一則友善的訊息回覆"),
            ("news", "在內建瀏覽器找一篇最近的 AI 新聞，摘要三個重點"),
            ("web", "在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較"),
            ("shopping", "在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點"),
            ("remember", "記住我偏好使用繁體中文，回答簡短一點"),
            ("recall", "你記得我有哪些偏好？")
        ]
        for (id, text) in cases {
            let example = app.buttons["chat.emptyExample." + id]
            revealLearningElement(example, in: app)
            XCTAssertTrue(example.isHittable)
            example.tap()
            assertDraft(text, in: app)
            XCTAssertTrue(app.buttons["chat.send"].isEnabled)
            XCTAssertFalse(app.staticTexts["chat.message.0.user"].exists)
            XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        }
    }

    /// Exercises the real AX hierarchy at the largest SwiftUI Dynamic Type size.
    /// This does not claim that the VoiceOver screen reader was enabled.
    func testStoreExamplesRemainScrollableAndAccessibleAtLargestText() throws {
        executionTimeAllowance = 600
        let app = launchApp()
        let first = app.buttons["chat.emptyExample.reply"]
        revealLearningElement(first, in: app)
        XCTAssertTrue(first.isHittable)
        let regularHeight = first.frame.height
        XCTAssertGreaterThan(regularHeight, 0)
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", UUID().uuidString,
                               "-UITestResetStorage", "-UITestChatAccessibilitySize", "-WoowSkipOnboarding"]
        app.launchEnvironment = [:]
        app.launch()
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        let draft = chatDraftControl(in: app)
        let microphone = app.buttons["chat.voice"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        XCTAssertEqual(microphone.label, "語音輸入")
        let cases = [
            ("reply", "幫我寫一則友善的訊息回覆"),
            ("news", "在內建瀏覽器找一篇最近的 AI 新聞，摘要三個重點"),
            ("web", "在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較"),
            ("shopping", "在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點"),
            ("remember", "記住我偏好使用繁體中文，回答簡短一點"),
            ("recall", "你記得我有哪些偏好？")
        ]
        for (index, item) in cases.enumerated() {
            let button = app.buttons["chat.emptyExample." + item.0].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), item.0)
            XCTAssertEqual(button.label, item.1, "AX must expose the complete store text")
            try revealExampleEdge(button, bottom: false, transcript: transcript, draft: draft, microphone: microphone, app: app)
            if index == 0 {
                XCTAssertGreaterThan(button.frame.height, regularHeight * 1.25, "The accessibility size must actually enlarge the row")
            }
            // Audit the real visible screen. A row taller than the visible transcript
            // (an iPhone SE at the largest size, with the input bar and the UI-test
            // banner) is cut by the scroll view, not truncated: the reader scrolls to
            // the rest. Text inside a fully visible element must never be clipped.
            let visibleTranscript = transcript.frame.intersection(app.frame)
            try app.performAccessibilityAudit(for: [.textClipped]) { issue in
                guard let frame = issue.element?.frame, !frame.isEmpty else { return false }
                return !visibleTranscript.contains(frame)
            }
            try revealExampleEdge(button, bottom: true, transcript: transcript, draft: draft, microphone: microphone, app: app)
            let visible = button.frame.intersection(transcript.frame).intersection(app.frame)
            XCTAssertGreaterThanOrEqual(visible.height, 44, "An exposed part of the button must be tappable")
            XCTAssertGreaterThanOrEqual(visible.width, 44)
            let point = button.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: visible.midX - button.frame.minX, dy: visible.midY - button.frame.minY))
            point.tap()
            assertDraft(item.1, in: app)
            XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
            assertComposerUnobscured(transcript: transcript, draft: draft, microphone: microphone, app: app)
        }
        attachScreenshot("examples-accessibility-largest-text", in: app)
    }

    private func assertComposerUnobscured(transcript: XCUIElement, draft: XCUIElement,
                                          microphone: XCUIElement, app: XCUIApplication,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(draft.isHittable, "Draft is available", file: file, line: line)
        XCTAssertTrue(microphone.isHittable, "Voice control is available", file: file, line: line)
        let view = app.frame
        XCTAssertTrue(view.contains(draft.frame), "Draft stays on screen", file: file, line: line)
        XCTAssertTrue(view.contains(microphone.frame), "Voice control stays on screen", file: file, line: line)
        XCTAssertTrue(transcript.frame.intersection(draft.frame).isEmpty, "Examples must not cover draft", file: file, line: line)
        XCTAssertTrue(transcript.frame.intersection(microphone.frame).isEmpty, "Examples must not cover voice", file: file, line: line)
        XCTAssertTrue(draft.frame.intersection(microphone.frame).isEmpty, "Draft and voice must not overlap", file: file, line: line)
    }

    private func revealExampleEdge(_ button: XCUIElement, bottom: Bool, transcript: XCUIElement,
                                   draft: XCUIElement, microphone: XCUIElement, app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) throws {
        for _ in 0..<70 {
            assertComposerUnobscured(transcript: transcript, draft: draft, microphone: microphone, app: app, file: file, line: line)
            let viewport = transcript.frame.intersection(app.frame).insetBy(dx: 4, dy: 8)
            XCTAssertGreaterThan(viewport.height, 80, "There must be usable scrolling space", file: file, line: line)
            let frame = button.frame
            let edge = bottom ? frame.maxY - 8 : frame.minY + 8
            if edge >= viewport.minY && edge <= viewport.maxY { return }
            let desired = min(max(edge, viewport.minY + 12), viewport.maxY - 12)
            let motion = min(viewport.height * 0.35, max(18, abs(edge - desired)))
            let sign: CGFloat = edge > viewport.maxY ? -1 : 1
            let origin = transcript.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - transcript.frame.minX,
                                                   dy: viewport.midY - transcript.frame.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: sign * motion))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Could not scroll to the \(bottom ? "bottom" : "top") of \(button.identifier)", file: file, line: line)
    }

    func testComposerGrowsThenScrollsAtFiveLinesAndAttachPanelKeepsDraft() {
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

        let attach = app.buttons["chat.attach.toggle"]
        let send = app.buttons["chat.send"]
        for control in [draft, attach, send] {
            XCTAssertFalse(control.frame.isEmpty)
            XCTAssertLessThanOrEqual(control.frame.maxY, mikaUnobscuredBottom(in: app),
                                     "Composer controls must remain above the keyboard on a compact iPhone.")
        }
        XCTAssertTrue(attach.isHittable)
        XCTAssertTrue(send.isEnabled, "A typed draft is sendable; a missing model is explained on tap.")
        // Raw frames for the keyboard-reserve review (ChatKeyboardDock).
        print("WOOW_FRAMES keyboard-up draft=\(draft.frame) attach=\(attach.frame) send=\(send.frame) "
              + "keyboard=\(app.keyboards.firstMatch.frame) unobscuredBottom=\(mikaUnobscuredBottom(in: app)) window=\(app.frame)")
        let done = app.buttons["chat.dismissKeyboard"]
        waitUntilHittable(done)
        done.tap()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 10), .completed)
        XCTAssertEqual(draft.value as? String, expected)

        // "+" opens the attach panel in the keyboard's place; × brings the keyboard back. The draft survives both.
        waitUntilHittable(attach)
        attach.tap()
        XCTAssertTrue(app.otherElements["chat.attach.panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat.attach.camera"].exists && app.buttons["chat.attach.album"].exists
                      && app.buttons["chat.attach.files"].exists, "The panel offers camera, album and files, as on Android.")
        print("WOOW_FRAMES panel-open draft=\(draft.frame) send=\(send.frame) panel=\(app.otherElements["chat.attach.panel"].frame) "
              + "keyboardExists=\(app.keyboards.firstMatch.exists)")
        attach.tap()
        let panelGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.otherElements["chat.attach.panel"])
        XCTAssertEqual(XCTWaiter.wait(for: [panelGone], timeout: 5), .completed)
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        print("WOOW_FRAMES panel-closed draft=\(draft.frame) send=\(send.frame) keyboard=\(app.keyboards.firstMatch.frame)")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, expected)
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
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
        // As on the Play build, the form says why and offers no save for plain HTTP.
        let problem = app.staticTexts["setup.urlProblem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("https://"))
        let save = app.buttons["settings.save"]
        revealSettings(save, in: app)
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(app.buttons["setup.test"].isEnabled)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "models.provider.")).firstMatch.exists)
        replaceBaseURL(fixtureURL, in: app)
        XCTAssertFalse(problem.exists)
        self.save(in: app)
        confirmModelSave(in: app)
        assertSaved(in: app, tested: false)
        // As on the Play build, an untested save chooses no main model: 選主模型
        // tests the typed model first, then asks for the consent.
        XCTAssertTrue(app.buttons["models.provider.model.example.invalid"].exists)
        XCTAssertTrue(app.buttons["models.role.main"].label.contains("未設定"))
        chooseMainAfterUntestedSave("ui-test-model", in: app)
        returnFromModelSettings(in: app)
        // Like Android, the Model row names the provider (here its host), not the model ID.
        let modelRow = app.buttons["settings.modelJump"]
        XCTAssertTrue(modelRow.label.contains("model.example.invalid"))
        XCTAssertFalse(modelRow.label.contains("ui-test-model"))
        // With a model, the status card moves on to the next problem: notifications are off.
        XCTAssertEqual(app.staticTexts["settings.status"].label, "通知未允許")
        XCTAssertEqual(app.buttons["settings.status.fix"].label, "允許")
        openSection("chat", in: app)
        send("Hello fixture 17", in: app)
        assertReply("測試回覆：Hello fixture 17", in: app)
        // Like Play, the drawer lists the saved chat; its note says it is kept encrypted here.
        app.buttons["chat.menu"].tap()
        let boundary = app.staticTexts["drawer.recent.boundary"]
        XCTAssertTrue(boundary.waitForExistence(timeout: 10))
        XCTAssertTrue(boundary.label.contains("此裝置已加密保存"), boundary.label)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                       "drawer.recent.row.", "Hello fixture 17")).firstMatch
            .waitForExistence(timeout: 10))
        app.buttons["drawer.close"].tap()
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
        // The key stays with its provider, whose address cannot be edited.
        openModelProvider("model.example.invalid", in: app)
        XCTAssertEqual(app.staticTexts["provider.keyStatus"].label, "已儲存")
        XCTAssertTrue(app.descendants(matching: .any)["provider.url"].label.contains("model.example.invalid/v1"))
        XCTAssertFalse(app.textFields["settings.baseURL"].exists)
        returnFromModelProvider("model.example.invalid", in: app)
        // Another host is another provider. Left blank, its key stays empty: the
        // first provider's key never goes there, and its model does not become main.
        let add = app.buttons["models.addProvider"]
        revealSettings(add, in: app)
        add.tap()
        let custom = app.buttons["setup.preset.custom"]
        revealSettings(custom, in: app)
        custom.tap()
        fillForm(in: app, baseURL: "https://other.example.invalid/v1", model: "other-model", key: nil)
        save(in: app)
        confirmModelSave(in: app)
        let notice = app.staticTexts["settings.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("other.example.invalid"))
        openModelProvider("other.example.invalid", in: app)
        XCTAssertEqual(app.staticTexts["provider.keyStatus"].label, "沒有填")
        returnFromModelProvider("other.example.invalid", in: app)
        XCTAssertTrue(app.buttons["models.role.main"].label.contains("ui-test-model"))
        returnFromModelSettings(in: app)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        openSection("settings", in: relaunched)
        openModelSettings(in: relaunched)
        openModelProvider("model.example.invalid", in: relaunched)
        XCTAssertEqual(relaunched.staticTexts["provider.keyStatus"].label, "已儲存")
        returnFromModelProvider("model.example.invalid", in: relaunched)
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

    func testSavedModelConnectionTestDoesNotUseUnsavedAddress() {
        let app = launchApp()
        fillConfiguration(in: app)
        let test = app.buttons["setup.test"]
        revealSettings(test, in: app)
        XCTAssertTrue(test.isEnabled)
        test.tap()
        // The test call used the typed address, model and key. Saving the first
        // main model still asks for the consent before anything is stored.
        agreeToModelConsent(in: app)
        let notice = app.staticTexts["settings.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("測試通過"))
        XCTAssertFalse(app.staticTexts["settings.error"].exists)
        // A provider that passed has nothing to test again, and its address is fixed.
        openModelProvider("model.example.invalid", in: app)
        XCTAssertFalse(app.buttons["provider.retest"].exists)
        XCTAssertFalse(app.textFields["settings.baseURL"].exists)
        returnFromModelProvider("model.example.invalid", in: app)
        returnFromModelSettings(in: app)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        openSection("settings", in: relaunched); openModelSettings(in: relaunched)
        let row = relaunched.buttons["models.provider.model.example.invalid"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(row.label.contains("沒測試通過"), "A provider that passed carries no warning")
        returnFromModelSettings(in: relaunched)
    }

    func testDelayedConnectionEditsCannotPublishOldResult() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The delayed connection fixture requires an isolated simulator")
        #else
        executionTimeAllowance = 300
        for field in ["url", "model", "key"] {
            let app = launchApp(delayedConnection: true)
            fillConfiguration(in: app)
            startDelayedConnection(in: app, started: 1, released: 0, settled: 0)
            switch field {
            case "url": replaceBaseURL("https://other.example.invalid/v1", in: app)
            case "model":
                let model = app.textFields["settings.model"]
                revealSettings(model, in: app, upward: false)
                model.tap(); model.typeText("x\n")
            default:
                let key = app.secureTextFields["settings.apiKey"]
                revealSettings(key, in: app, upward: false)
                key.tap(); key.typeText("x\n")
            }
            // Android edit(): a change drops the running test, and its late pass saves nothing.
            waitTestButton("測試並儲存", in: app)
            waitConnectionFixture(in: app, started: 1, cancelled: 1, released: 0, settled: 0)
            releaseDelayedConnection(in: app, started: 1, cancelled: 1, released: 1, settled: 1)
            waitTestButton("測試並儲存", in: app)
            assertNothingSaved(in: app, "after a \(field) edit")
            app.terminate()
        }
        let app = launchApp(delayedConnection: true)
        fillConfiguration(in: app)
        startDelayedConnection(in: app, started: 1, released: 0, settled: 0)
        tapFixtureRelease(in: app)
        agreeToModelConsent(in: app)
        let notice = app.staticTexts["settings.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("測試通過"))
        returnFromModelSettings(in: app); openSection("chat", in: app)
        send("Saved connection still works", in: app)
        assertReply("測試回覆：Saved connection still works", in: app)
        #endif
    }

    func testDelayedConnectionCancelSaveAndLeaveCannotPublishOldResult() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The delayed connection fixture requires an isolated simulator")
        #else
        executionTimeAllowance = 300
        let app = launchApp(delayedConnection: true)
        fillConfiguration(in: app)
        // Leaving the page drops the running test; its late pass saves nothing.
        startDelayedConnection(in: app, started: 1, released: 0, settled: 0)
        returnFromModelSettings(in: app); openModelSettings(in: app)
        waitConnectionFixture(in: app, started: 1, cancelled: 1, released: 0, settled: 0)
        releaseDelayedConnection(in: app, started: 1, cancelled: 1, released: 1, settled: 1)
        assertNothingSaved(in: app, "after leaving the page")
        // Saved without a test, then added again and the form cancelled while
        // its test is pending: the late pass neither saves nor marks it tested.
        fillForm(in: app)
        save(in: app); confirmModelSave(in: app); assertSaved(in: app, tested: false)
        let add = app.buttons["models.addProvider"]
        revealSettings(add, in: app)
        add.tap()
        let custom = app.buttons["setup.preset.custom"]
        revealSettings(custom, in: app)
        custom.tap()
        fillForm(in: app)
        startDelayedConnection(in: app, started: 2, released: 1, settled: 1)
        let cancel = app.buttons["setup.cancel"]
        revealSettings(cancel, in: app, upward: false)
        cancel.tap()
        waitConnectionFixture(in: app, started: 2, cancelled: 2, released: 1, settled: 1)
        releaseDelayedConnection(in: app, started: 2, cancelled: 2, released: 2, settled: 2)
        XCTAssertFalse(app.buttons["consent.agree"].exists, "A cancelled test must not ask to save")
        openModelProvider("model.example.invalid", in: app)
        XCTAssertTrue(app.staticTexts["provider.untested"].exists)
        // 重新測試 on the provider's page uses its saved address, model and key.
        let retest = app.buttons["provider.retest"]
        revealSettings(retest, in: app)
        retest.tap()
        waitConnectionFixture(in: app, started: 3, cancelled: 2, released: 2, settled: 2)
        releaseDelayedConnection(in: app, started: 3, cancelled: 2, released: 3, settled: 3)
        let status = app.staticTexts["provider.retestStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("測試通過"))
        XCTAssertFalse(app.staticTexts["provider.untested"].exists)
        // The tested model becomes the main model from its 用作 sheet, after the consent.
        let model = app.buttons["provider.model.ui-test-model"]
        revealSettings(model, in: app)
        model.tap()
        let useAsMain = app.buttons["useAs.main"]
        XCTAssertTrue(useAsMain.waitForExistence(timeout: 10))
        useAsMain.tap()
        agreeToModelConsent(in: app)
        returnFromModelProvider("model.example.invalid", in: app)
        XCTAssertTrue(app.buttons["models.role.main"].label.contains("ui-test-model"))
        returnFromModelSettings(in: app); openSection("chat", in: app)
        send("Saved after cancellation", in: app)
        assertReply("測試回覆：Saved after cancellation", in: app)
        #endif
    }

    func testDelayedConnectionBackgroundCannotPublishOldResult() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The delayed connection fixture requires an isolated simulator")
        #else
        executionTimeAllowance = 300
        let app = launchApp(delayedConnection: true)
        fillConfiguration(in: app)
        startDelayedConnection(in: app, started: 1, released: 0, settled: 0)
        XCUIDevice.shared.press(.home)
        let background = NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: background, object: nil)], timeout: 10), .completed)
        app.activate()
        waitTestButton("測試並儲存", in: app)
        waitConnectionFixture(in: app, started: 1, cancelled: 1, released: 0, settled: 0)
        releaseDelayedConnection(in: app, started: 1, cancelled: 1, released: 1, settled: 1)
        waitTestButton("測試並儲存", in: app)
        assertNothingSaved(in: app, "after the app went to the background")
        startDelayedConnection(in: app, started: 2, released: 1, settled: 1)
        tapFixtureRelease(in: app)
        agreeToModelConsent(in: app)
        let notice = app.staticTexts["settings.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertTrue(notice.label.contains("測試通過"))
        #endif
    }

    /// App Review 5.1.2(i): the first save that makes a main model asks first,
    /// names the service, its host and what would be sent, and declining
    /// saves and sends nothing.
    func testConsentNamesTheHostAndDecliningSavesNothing() {
        let app = launchApp()
        fillConfiguration(in: app)
        tapTestAndSave(in: app)
        let title = app.staticTexts["consent.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "要把內容傳給 model.example.invalid 嗎？")
        XCTAssertTrue(app.staticTexts["consent.body"].label.contains("（model.example.invalid）"))
        for item in ["chat", "attachments", "images", "profile", "memory", "skills", "memoryOrganizing", "web",
                     "researchJudgment", "mcp"] {
            XCTAssertTrue(app.descendants(matching: .any)["consent.item." + item].exists, "Consent lists \(item)")
        }
        XCTAssertTrue(app.staticTexts["consent.decline.note"].label.contains("什麼都不會傳出去"))
        XCTAssertTrue(app.descendants(matching: .any)["consent.privacyPolicy"].exists)
        answerModelConsent(agree: false, in: app)
        let notice = app.staticTexts["settings.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(notice.label.contains("沒有儲存"))
        assertNothingSaved(in: app, "after declining")
        XCTAssertTrue(app.buttons["models.role.main"].label.contains("未設定"))
        // The form keeps what was typed; agreeing after the next test stores it.
        tapTestAndSave(in: app)
        agreeToModelConsent(in: app)
        assertSaved(in: app)
        XCTAssertTrue(app.buttons["models.role.main"].label.contains("ui-test-model"))
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        send("After consent", in: app)
        assertReply("測試回覆：After consent", in: app)
    }

    func testKeychainWriteFailureDoesNotPublishConfiguration() {
        let app = launchApp(keychainWriteFails: true)
        fillConfiguration(in: app)
        save(in: app)
        confirmModelSave(in: app)
        XCTAssertTrue(app.staticTexts["settings.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.error"].label.contains("Keychain"))
        returnFromModelSettings(in: app)
        app.terminate()
        let relaunched = launchApp(resetStorage: false)
        XCTAssertEqual(relaunched.staticTexts["chat.status"].label, "尚未設定模型")
        XCTAssertFalse(relaunched.buttons["chat.send"].isEnabled)
    }

    func testRemovingConfigurationKeepsDraftAndExplainsMissingModel() {
        let app = launchApp()
        enterChatDraft("Draft after key removal", in: app)
        configure(in: app)
        // Like the Play build, a provider is removed with its key from its own page.
        deleteModelProvider("model.example.invalid", in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].label.contains("已刪除"))
        returnFromModelSettings(in: app)
        openSection("chat", in: app)
        assertDraft("Draft after key removal", in: app)
        // 去設定 dismisses the card and opens Settings, like Android's card.
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.isEnabled)
        waitUntilHittable(send)
        send.tap()
        let openSettings = app.buttons["chat.sendBlocked.openSettings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        XCTAssertEqual(openSettings.label, "去設定")
        waitUntilHittable(openSettings)
        openSettings.tap()
        XCTAssertTrue(app.staticTexts["settings.status"].waitForExistence(timeout: 5))
        openSection("chat", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["chat.sendBlocked"].exists)
        assertDraft("Draft after key removal", in: app)
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

    private func launchApp(resetStorage: Bool = true, keychainWriteFails: Bool = false,
                           delayedConnection: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        if resetStorage { app.launchArguments.append("-UITestResetStorage") }
        if keychainWriteFails { app.launchArguments.append("-UITestKeychainWriteFailure") }
        if delayedConnection { app.launchArguments.append("-UITestModelConnectionDelay") }
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["uitest.banner"].exists)
        attachScreenshot("launch", in: app)
        return app
    }

    private func fillConfiguration(in app: XCUIApplication, baseURL: String? = nil) {
        openSection("settings", in: app)
        openModelSettings(in: app)
        fillForm(in: app, baseURL: baseURL ?? fixtureURL)
    }

    /// The add form's 自訂 fields; a nil key leaves the key blank.
    private func fillForm(in app: XCUIApplication, baseURL: String? = nil, model: String = "ui-test-model",
                          key: String? = "fixture-only-not-a-real-key") {
        let address = app.textFields["settings.baseURL"]
        revealSettings(address, in: app)
        enter(baseURL ?? fixtureURL, into: address)
        let modelField = app.textFields["settings.model"]
        revealSettings(modelField, in: app)
        enter(model, into: modelField)
        if let key {
            let keyField = app.secureTextFields["settings.apiKey"]
            revealSettings(keyField, in: app)
            enter(key, into: keyField)
        }
    }

    /// A main model: 測試並儲存 passes on the fixture model, then the consent.
    private func configure(in app: XCUIApplication) {
        fillConfiguration(in: app)
        tapTestAndSave(in: app)
        agreeToModelConsent(in: app)
        assertSaved(in: app)
    }

    /// 測試並儲存; the consent screen follows when the save makes the first main model.
    private func tapTestAndSave(in app: XCUIApplication) {
        let test = app.buttons["setup.test"]
        revealSettings(test, in: app)
        XCTAssertTrue(test.isEnabled)
        test.tap()
    }

    /// 測試並儲存 reads 正在測試… while its test runs.
    private func waitTestButton(_ expected: String, in app: XCUIApplication) {
        let test = app.buttons["setup.test"].firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: test)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func assertNothingSaved(in app: XCUIApplication, _ when: String) {
        XCTAssertFalse(app.buttons["consent.agree"].exists, "A stale result must not ask to save \(when)")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "models.provider.")).firstMatch.exists,
                       "A stale result must save nothing \(when)")
    }

    private func waitConnectionFixture(in app: XCUIApplication, started: Int, cancelled: Int, released: Int, settled: Int) {
        let indicator = app.staticTexts["settings.connectionFixture"].firstMatch
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@",
            "Fixture: \(started),\(cancelled),\(released),\(settled)"), object: indicator)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }

    private func startDelayedConnection(in app: XCUIApplication, started: Int, released: Int, settled: Int) {
        let test = app.buttons["setup.test"]
        revealSettings(test, in: app)
        XCTAssertTrue(test.isEnabled)
        test.tap()
        waitConnectionFixture(in: app, started: started, cancelled: released, released: released, settled: settled)
        waitTestButton("正在測試…", in: app)
    }

    private func releaseDelayedConnection(in app: XCUIApplication, started: Int, cancelled: Int, released: Int, settled: Int) {
        tapFixtureRelease(in: app)
        waitConnectionFixture(in: app, started: started, cancelled: cancelled, released: released, settled: settled)
    }

    /// Releases the pending fixture reply; a pass then shows the consent screen over the page.
    private func tapFixtureRelease(in app: XCUIApplication) {
        let release = app.buttons["settings.connectionFixture.release"]
        revealSettings(release, in: app)
        XCTAssertTrue(release.isEnabled)
        release.tap()
    }

    /// 不測試，直接儲存; confirmModelSave answers its question.
    private func save(in app: XCUIApplication) {
        let save = app.buttons["settings.save"]
        revealSettings(save, in: app)
        save.tap()
    }

    private func assertSaved(in app: XCUIApplication, tested: Bool = true) {
        XCTAssertTrue(app.staticTexts["settings.notice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["settings.notice"].label.contains(tested ? "測試通過" : "沒有測試過"))
        XCTAssertFalse(app.staticTexts["settings.error"].exists)
    }

    /// Deletes the typed address from its end, then types the new one.
    private func replaceBaseURL(_ value: String, in app: XCUIApplication) {
        let field = app.textFields["settings.baseURL"]
        revealSettings(field, in: app, upward: false)
        let current = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + value + "\n")
        XCTAssertEqual(field.value as? String, value)
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

    /// Like the Android store build, a typed draft can be sent before a model is
    /// set up; the tap shows 還不能開始任務 instead of doing nothing, starts no
    /// request, and 知道了 dismisses the card.
    private func assertSendExplainsMissingModel(in app: XCUIApplication,
                                                file: StaticString = #filePath, line: UInt = #line) {
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.isEnabled, file: file, line: line)
        waitUntilHittable(send, file: file, line: line)
        send.tap()
        let card = app.descendants(matching: .any)["chat.sendBlocked"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(card.staticTexts["還不能開始任務"].exists, file: file, line: line)
        XCTAssertTrue(card.staticTexts["還缺:還沒有能用的模型"].exists, file: file, line: line)
        XCTAssertEqual(app.buttons["chat.sendBlocked.openSettings"].label, "去設定", file: file, line: line)
        XCTAssertFalse(app.buttons["chat.cancel"].exists, "No request may start without a model.", file: file, line: line)
        attachScreenshot("unconfigured-send-explained", in: app)
        let dismiss = app.buttons["chat.sendBlocked.dismiss"]
        XCTAssertEqual(dismiss.label, "知道了", file: file, line: line)
        waitUntilHittable(dismiss, file: file, line: line)
        dismiss.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
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
        // The expectation first checks about 1 s after the wait starts. In CI run
        // 43364763538 (16 Pro Max) a burst of simulator widget extensions made each
        // AX query take 2-4 s, and the on-screen base URL field's first check was
        // still running when 5 s ran out. Use this file's usual 10 s budget.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, file: file, line: line)
    }

    private func assertDraft(_ expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = chatDraftControl(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        let expectedValue = expected.isEmpty ? "輸入訊息" : expected
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@ OR value == %@", expected, expectedValue), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed, file: file, line: line)
    }
}
