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

    func testAboutHeroAndDiagnosticsInEverySupportedLanguage() {
        let cases: [(String, String, String, String)] = [
            ("(zh-Hant)", "關於渥屋助理", "你的私人助理，替你把事辦成", "診斷資訊"),
            ("(zh-Hans)", "关于渥屋助理", "你的私人助理，替你把事办成", "诊断信息"),
            ("(en)", "About woowtech agent", "Your personal assistant, getting things done for you", "Diagnostic information")
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
            let diagnostics = app.buttons["settings.about.diagnostics"]
            revealLearningElement(diagnostics, in: app)
            XCTAssertTrue(diagnostics.isHittable); diagnostics.tap()
            XCTAssertTrue(app.navigationBars[diagnosticsTitle].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["settings.about.diagnostics.report"].exists)
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

    /// Uses the real Settings Picker and a fresh Debug defaults namespace.
    /// The second launch deliberately omits reset to exercise persistence.
    func testMCPModelCallLimitPersistsThroughSettingsAndRelaunch() {
        executionTimeAllowance = 300
        let id = UUID().uuidString
        launchMCPSetting(language: "(zh-Hant)", namespace: id, reset: true)
        let title = "MCP 模型呼叫上限"
        openMCPModelLimit(title: title)
        assertMCPPickerValue("12")
        assertMCPDetails(["遠端 MCP 工具與資源每次須核准", "合計最多執行 6 次", "本機操作不計入", "本機記憶搜尋不經遠端核准", "本機變更另須審核"])
        chooseMCPModelLimit("3")
        assertMCPPickerValue("3")
        let bar = app.navigationBars[title]
        let back = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10) && back.isHittable)
        back.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
        assertMCPSettingsRowValue("3")
        app.terminate()
        launchMCPSetting(language: "(zh-Hant)", namespace: id, reset: false)
        assertMCPSettingsRowValue("3")
        openMCPModelLimit(title: title)
        assertMCPPickerValue("3")
        assertMCPDetails(["遠端 MCP 工具與資源每次須核准", "本機記憶搜尋不經遠端核准"])
    }

    func testMCPModelCallLimitExplanationsInThreeLanguages() {
        executionTimeAllowance = 300
        let cases: [(String, String, [String])] = [
            ("(zh-Hant)", "MCP 模型呼叫上限", ["遠端 MCP 工具與資源每次須核准", "合計最多執行 6 次", "本機操作不計入", "本機記憶搜尋不經遠端核准", "本機變更另須審核"]),
            ("(zh-Hans)", "MCP 模型调用上限", ["远程 MCP 工具与资源每次须批准", "合计最多执行 6 次", "本地操作不计入", "本地记忆搜索不经远程批准", "本地更改另须审核"]),
            ("(en)", "MCP model call limit", ["Remote MCP tools and resources require approval for each operation", "combined limit of 6", "Local actions do not count", "Local memory searches do not use remote approval", "local changes require separate review"])
        ]
        for (language, title, phrases) in cases {
            app.terminate()
            launchMCPSetting(language: language, namespace: UUID().uuidString, reset: true)
            openMCPModelLimit(title: title)
            assertMCPPickerValue("12")
            assertMCPDetails(phrases)
        }
    }

    private func launchMCPSetting(language: String, namespace: String, reset: Bool) {
        app.launchArguments = ["-AppleLanguages", language, "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]
        app.launch()
        navigateMikaSection("settings", in: app)
    }
    private func openMCPModelLimit(title: String) {
        let link = app.buttons["settings.mcpModelCallLimit"].firstMatch
        revealLearningElement(link, in: app)
        XCTAssertTrue(link.exists && link.isEnabled && link.isHittable)
        link.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
    }
    private func mcpPicker() -> XCUIElement {
        // A different Form Picker was recorded as a Button on three iPhone
        // runtimes. This Picker/iPad role has not yet been observed natively.
        let button = app.buttons["settings.mcpModelCallLimit.picker"].firstMatch
        if button.exists { return button }
        return app.descendants(matching: .any).matching(identifier: "settings.mcpModelCallLimit.picker").firstMatch
    }
    private func recordMCPAccessibility(_ name: String, _ element: XCUIElement) {
        guard element.exists else { return }
        XCTContext.runActivity(named: name) { activity in
            let detail = "elementType=\(element.elementType.rawValue)\n" + element.debugDescription
            let attachment = XCTAttachment(string: detail)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
    private func assertMCPPickerValue(_ expected: String) {
        let picker = mcpPicker()
        revealLearningElement(picker, in: app)
        recordMCPAccessibility("MCP picker", picker)
        let condition = NSPredicate { _, _ in
            let combined = picker.label + " " + String(describing: picker.value ?? "")
            return combined.range(of: "(?<![0-9])" + expected + "(?![0-9])", options: .regularExpression) != nil
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: picker)], timeout: 10),
                       .completed, "Picker did not expose selected value; element: \(picker.debugDescription)")
    }
    private func assertMCPSettingsRowValue(_ expected: String) {
        let row = app.buttons["settings.mcpModelCallLimit"].firstMatch
        revealLearningElement(row, in: app)
        let condition = NSPredicate { _, _ in
            let combined = row.label + " " + String(describing: row.value ?? "")
            return combined.range(of: "(?<![0-9])" + expected + "(?![0-9])", options: .regularExpression) != nil
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: row)], timeout: 10),
                       .completed, "Settings row did not expose saved value; element: \(row.debugDescription)")
    }
    private func assertMCPDetails(_ phrases: [String]) {
        guard let first = phrases.first else { XCTFail("Expected localized phrases"); return }
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", first)).firstMatch
        revealLearningElement(text, in: app, visibility: .readableText)
        XCTAssertTrue(text.exists)
        for phrase in phrases { XCTAssertTrue(text.label.contains(phrase), "Missing localized explanation: \(phrase)") }
    }
    private func chooseMCPModelLimit(_ value: String) {
        let picker = mcpPicker()
        revealLearningElement(picker, in: app)
        if picker.elementType == .pickerWheel {
            recordMCPAccessibility("MCP picker wheel", picker)
            picker.adjust(toPickerWheelValue: value)
            return
        }
        let nestedWheel = picker.pickerWheels.firstMatch
        if nestedWheel.exists {
            recordMCPAccessibility("MCP nested picker wheel", nestedWheel)
            nestedWheel.adjust(toPickerWheelValue: value)
            return
        }
        guard picker.isHittable else { XCTFail("Picker is not tappable: \(picker.debugDescription)"); return }
        picker.tap()
        let wheel = app.pickerWheels.firstMatch
        if wheel.exists && wheel.isHittable {
            XCTAssertEqual(app.pickerWheels.count, 1, "Ambiguous picker wheels")
            recordMCPAccessibility("MCP presented picker wheel", wheel)
            wheel.adjust(toPickerWheelValue: value)
            return
        }
        // Menu popovers and navigation-style pickers expose different AX
        // element roles across device families. Match the exact option label;
        // never use blind coordinates or silently accept an unselected value.
        let options = [app.buttons[value].firstMatch, app.menuItems[value].firstMatch,
                       app.cells[value].firstMatch, app.staticTexts[value].firstMatch]
        for _ in 0..<20 {
            if let option = options.first(where: { $0.exists && $0.isHittable }) {
                recordMCPAccessibility("MCP chosen option", option)
                option.tap(); return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("Picker did not expose an actionable option \(value); picker: \(picker.debugDescription)")
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
