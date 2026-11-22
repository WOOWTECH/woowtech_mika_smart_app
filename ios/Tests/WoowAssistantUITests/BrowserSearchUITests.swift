import XCTest

final class BrowserSearchUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 180 }
    override func tearDownWithError() throws { app.terminate() }

    func testCustomSearchQueryAndSettingsSurviveRelaunch() {
        launch()
        let settings = app.buttons["browser.searchEngine.open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(settings.label.contains("Google"))
        tap(settings)
        XCTAssertTrue(app.buttons["browser.searchEngine.select.google"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["browser.searchEngine.select.google"].value as? String, "已選取")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.searchEngine.remove.custom:")).firstMatch.exists,
                       "The fresh namespace must contain no previously saved custom engine")
        tap(app.buttons["browser.searchEngine.select.bing"], scroll: true)
        XCTAssertEqual(app.buttons["browser.searchEngine.select.bing"].value as? String, "已選取")
        let name = app.textFields["browser.searchEngine.name"]
        enter("Fixture Search", in: name, scroll: true)
        // Use the form's real Next action. With the name keyboard open, the
        // template is obscured; scrolling via the background browser's tab bar
        // cannot establish the presented sheet's visible input area.
        name.typeText("\n")
        let template = app.textFields["browser.searchEngine.template"]
        enter("https://research.example.invalid/search?q=%s&lang=en", in: template, scroll: true)
        // Submit the single-line native field to resign focus. Do not close
        // the settings sheet, patch its text, or press Add behind the keyboard.
        template.typeText("\n")
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 10), .completed)
        XCTAssertEqual(name.value as? String, "Fixture Search")
        XCTAssertEqual(template.value as? String, "https://research.example.invalid/search?q=%s&lang=en")
        let add = app.buttons["browser.searchEngine.add"]
        tap(add, scroll: true)
        tap(app.buttons["browser.searchEngine.close"])
        XCTAssertTrue(settings.label.contains("Fixture Search"))
        let address = app.textFields["browser.address"]
        enter("fixture cats & dogs/+%", in: address)
        address.typeText("\n")
        // Like Play's page bar, a search results page shows the searched words;
        // the pill's value is the full search URL.
        let query = app.buttons["browser.addressPill"]
        let searched = NSPredicate(format: "exists == true AND label CONTAINS %@", "fixture cats & dogs/+%")
        let status = app.staticTexts["browser.status"]
        // The pill can show the requested URL before WebKit finishes. History
        // is saved synchronously by didFinish, before the ready phase; wait
        // for that boundary within the existing budget before testing relaunch.
        let loadedSearch = NSPredicate { _, _ in
            searched.evaluate(with: query) && status.exists
                && (status.value as? String)?.hasPrefix("phase=ready;") == true
        }
        let loadedResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loadedSearch, object: nil)], timeout: 75)
        attachSearchContext("before-terminate")
        XCTAssertEqual(loadedResult, .completed)
        XCTAssertTrue((query.value as? String)?.contains("q=fixture%20cats%20%26%20dogs%2F%2B%25") == true)
        XCTAssertFalse(app.buttons["browser.searchEngine.open"].exists, "The engine choice is on the start page, as Play's engine note is.")
        XCTAssertFalse(app.staticTexts["browser.workspace.error"].exists,
                       "Completed navigation must save history without a workspace error before relaunch")
        launch()
        // Like the Play build, a relaunch opens the start page, and recent pages
        // (no library sheet) keep the search.
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.start.history.open.")).firstMatch
        let historyExists = history.waitForExistence(timeout: 10)
        attachSearchContext("after-relaunch")
        XCTAssertTrue(historyExists)
        XCTAssertFalse(query.exists)
        revealLearningElement(history, in: app)
        XCTAssertTrue(history.label.contains("搜尋：fixture cats & dogs/+%"))
        XCTAssertTrue(settings.label.contains("Fixture Search"))
        tap(history)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: searched, object: query)], timeout: 75), .completed)
        tap(app.buttons["browser.closePage"])
        tap(settings)
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "browser.searchEngine.remove.custom:")).firstMatch
        tap(remove, scroll: true)
        revealLearningElement(app.buttons["browser.searchEngine.select.google"], in: app)
        XCTAssertEqual(app.buttons["browser.searchEngine.select.google"].value as? String, "已選取")
        tap(app.buttons["browser.searchEngine.close"])
        XCTAssertTrue(settings.label.contains("Google"))
    }

    /// One read-only AX snapshot per boundary, including failed waits. Emit only
    /// this test's fixed QA values; never attach a hierarchy or arbitrary text.
    private func attachSearchContext(_ stage: String) {
        let args = app.launchArguments
        guard args.contains("-UITestMode"), !args.contains("-UITestBrowserNetwork"),
              let index = args.firstIndex(of: "-UITestNamespace"), args.indices.contains(index + 1),
              args[index + 1] == namespace else { return }
        var context: [String: Any] = ["stage": stage, "synthetic": true, "namespace": namespace,
                                     "epoch": Date().timeIntervalSince1970]
        do {
            let snapshot = try app.snapshot()
            var pending = [snapshot]
            var nodes: [String: XCUIElementSnapshot] = [:]
            var history: [XCUIElementSnapshot] = []
            let wanted: Set<String> = ["browser.status", "browser.addressPill", "browser.workspace.error",
                                       "browser.start.history.empty", "browser.searchEngine.open"]
            while let node = pending.popLast() {
                if wanted.contains(node.identifier) { nodes[node.identifier] = node }
                if node.identifier.hasPrefix("browser.start.history.open.") { history.append(node) }
                pending.append(contentsOf: node.children)
            }
            context["snapshot"] = "obtained"
            context["rootChildren"] = snapshot.children.count
            let status = nodes["browser.status"]?.value as? String
            let pattern = #"\Aphase=(idle|requested|started|committed|finished|observing|ready|failed|terminated);requested=[0-9]{1,10};started=[0-9]{1,10};committed=[0-9]{1,10};finished=[0-9]{1,10};observed=[0-9]{1,10};failed=[0-9]{1,10};terminated=[0-9]{1,10};elapsed_ms=[0-9]{1,10};failure=(none|cancelled|navigation_failed|navigation_timeout|observation_failed|observation_timeout|page_changed|policy_rejected|response_rejected|process_terminated)\z"#
            context["statusExists"] = nodes["browser.status"] != nil
            if let status {
                context["statusValue"] = status.utf8.count <= 512 && status.range(of: pattern, options: .regularExpression) != nil
                    ? status : "<unexpected-redacted>"
            } else { context["statusValue"] = NSNull() }
            let expectedURL = "https://research.example.invalid/search?q=fixture%20cats%20%26%20dogs%2F%2B%25&lang=en"
            context["pillExists"] = nodes["browser.addressPill"] != nil
            if let value = nodes["browser.addressPill"]?.value as? String {
                context["pillValue"] = value == expectedURL ? value : "<unexpected-redacted>"
            } else { context["pillValue"] = NSNull() }
            context["workspaceErrorExists"] = nodes["browser.workspace.error"] != nil
            context["historyCount"] = history.count
            context["historyMatchesFixtureQuery"] = history.contains { $0.label.contains("搜尋：fixture cats & dogs/+%") }
            context["emptyHistoryExists"] = nodes["browser.start.history.empty"] != nil
            context["engineExists"] = nodes["browser.searchEngine.open"] != nil
            if let label = nodes["browser.searchEngine.open"]?.label {
                context["engineLabel"] = label == "搜尋引擎：Fixture Search" ? label : "<unexpected-redacted>"
            } else { context["engineLabel"] = NSNull() }
        } catch { context["snapshot"] = "unavailable" } // Never include Error/NSError text.
        let data = try! JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "browser-search-" + stage
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        // This test owns a new UUID namespace. Clearing its empty WebKit store
        // adds an unrelated asynchronous reset before settings are usable. Both
        // launches keep this same isolated store to exercise actual persistence.
        app.launch()
        navigateMikaSection("browser", in: app)
    }

    private func enter(_ text: String, in field: XCUIElement, scroll: Bool = false) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field)
        assertVisibleField(field)
        field.tap()
        prepareKeyboard()
        // The real focus transition must put the entire field above the native
        // keyboard. Do not type into an offscreen or covered field.
        assertVisibleField(field)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Native field input must match exactly; no replacement or retyping repair")
    }

    private func assertVisibleField(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let frame = field.frame
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertTrue(app.frame.contains(frame), "Native input must be fully on screen", file: file, line: line)
        XCTAssertTrue(field.isHittable, "Native input must remain operable", file: file, line: line)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(frame.maxY, keyboard.frame.minY,
                                     "Native input must be fully above the keyboard", file: file, line: line)
        }
        let settingsNavigation = app.navigationBars["搜尋引擎"]
        if settingsNavigation.exists {
            XCTAssertGreaterThanOrEqual(frame.minY, settingsNavigation.frame.maxY,
                                        "Native input must be below the settings navigation bar", file: file, line: line)
        }
    }

    private func tap(_ element: XCUIElement, scroll: Bool = false) {
        if scroll { revealLearningElement(element, in: app) }
        ready(element)
        XCTAssertTrue(app.frame.contains(element.frame)); XCTAssertFalse(element.frame.isEmpty)
        element.tap()
    }

    private func ready(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10), .completed)
        }
    }

    // Same native English-keyboard selection and exact QuickPath introduction
    // gate used by the existing archive/profile/login UI tests. App stays zh-Hant.
    private func prepareKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissIntroduction()
        let keyboard = app.keyboards.firstMatch
        func latin() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        let globe = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Next keyboard", "下一個鍵盤"]
        )).firstMatch
        ready(globe); globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap(); dismissIntroduction()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latin() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, "Native Latin keys must be ready before fixture input")
    }

    private func dismissIntroduction() {
        let button = app.buttons["Continue"].firstMatch
        guard button.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."].firstMatch.exists)
        ready(button); button.tap()
        let gone = NSPredicate(format: "exists == false")
        if !gone.evaluate(with: button) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: button)], timeout: 5), .completed)
        }
    }
}
