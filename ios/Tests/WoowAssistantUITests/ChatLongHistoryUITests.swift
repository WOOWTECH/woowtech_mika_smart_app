import Foundation
import XCTest

/// One bounded native run per selector, through encrypted archive -> drawer -> ChatSession -> UI.
/// Seeded text and the one new model reply are synthetic. This is a rendering-pressure
/// reproduction, not evidence of real-provider performance or commercial device acceptance.
final class ChatLongHistoryUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private let probe = "Long history render probe"
    private var initialTurns = 0
    private var activePhase: String?
    private var phaseStarted: TimeInterval?
    private var timings: [[String: Any]] = []
    private var pageObservations: [[String: Int]] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    override func tearDownWithError() throws {
        // The run has not finished here: hasSucceeded is not a final verdict.
        // Record failures observed so far; xcresult owns the completed result.
        let failuresObservedBeforeTeardown = testRun?.failureCount ?? 0
        var report: [String: Any] = [
            "fixture": "long-history-v1", "synthetic": true, "namespace": namespace,
            "initialTurns": initialTurns, "initialMessages": initialTurns * 2,
            "maximumSeconds": 300, "phases": timings, "pages": pageObservations,
            "maximumRenderedMessages": 80,
            "failuresObservedBeforeTeardown": failuresObservedBeforeTeardown,
            "finalResultSource": "xcresult",
            "timingScope": "native XCTest actions and AX observations; includes automation overhead"
        ]
        if let activePhase, let phaseStarted {
            report["unfinishedPhase"] = activePhase
            report["unfinishedPhaseSeconds"] = ProcessInfo.processInfo.systemUptime - phaseStarted
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let summary = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        summary.name = "long-history-\(initialTurns)-timings.json"
        summary.lifetime = .keepAlways
        add(summary)
        print("LONG_HISTORY_RESULT " + String(decoding: data, as: UTF8.self))
        if failuresObservedBeforeTeardown > 0, app.state == .runningForeground {
            capture("long-history-failure-" + (activePhase ?? "assertion"))
        }
        app.terminate()
    }

    /// Exactly 1000 archived turns / 2000 messages. Turn 1001 renders but cannot
    /// be archived under the current production cap; assert that limitation explicitly.
    func testThousandTurnArchiveRemainsInteractiveAtCapacity() {
        exercise(turns: 1000, expectsArchiveLimit: true)
    }

    /// The companion scale verifies the successful save path: 999 -> 1000 turns,
    /// then a process restart and a real archive reopen retain the completed reply.
    func testThousandthTurnPersistsFrom999TurnArchive() {
        exercise(turns: 999, expectsArchiveLimit: false)
        exerciseBlockedSendOnEarlierPage()
    }

    private func exercise(turns: Int, expectsArchiveLimit: Bool) {
        initialTurns = turns
        phase("seed_launch") { launch(reset: true) }
        phase("cold_launch") { app.terminate(); launch(reset: false) }
        phase("open_history") { openHistory(lastIndex: turns * 2 - 1, marker: "LH-END-\(turns)") }
        phase("earliest_navigation") { visitEarliest(total: turns * 2) }
        phase("latest_navigation") { visitLatest(lastIndex: turns * 2 - 1, marker: "LH-END-\(turns)") }
        phase("keyboard_ready") {
            let draft = chatDraftControl(in: app)
            ready(draft); draft.tap(); prepareKeyboard()
        }
        phase("keyboard_input") { typeDraft(probe) }
        phase("send_to_completed_reply") {
            // Keep the keyboard up: exercise the same eager transcript under a reduced viewport.
            tap("chat.send")
            assertLabel(message(turns * 2, role: "user"), probe)
            let reply = message(turns * 2 + 1, role: "assistant")
            assertLabel(reply, "測試回覆：" + probe)
            assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
            XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
            if expectsArchiveLimit {
                assertLabel(app.staticTexts["chat.archiveNotice"].firstMatch,
                            "回覆已顯示，但本次對話未能保存；關閉程序後可能遺失。")
                print("LONG_HISTORY_CAPACITY expected=1000 attempted=1001 replyRendered=1 archiveSaved=0")
            } else {
                XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
            }
            assertVisibleReply(reply)
            assertBoundedPage(first: turns * 2 + 2 - 80, last: turns * 2 + 1, total: turns * 2 + 2)
            capture("long-history-completed-\(turns)")
        }
        phase("post_completion_interaction") {
            let draft = chatDraftControl(in: app)
            ready(draft); draft.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15))
            typeDraft("Still responsive")
            let panel = app.otherElements["chat.attach.panel"].firstMatch
            tap("chat.attach.toggle")
            XCTAssertTrue(panel.waitForExistence(timeout: 15))
            wait(NSPredicate(format: "exists == false"), on: app.keyboards.firstMatch, seconds: 15)
            XCTAssertEqual(draft.value as? String, "Still responsive")
            tap("chat.attach.toggle")
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15))
            wait(NSPredicate(format: "exists == false"), on: panel, seconds: 15)
            XCTAssertEqual(draft.value as? String, "Still responsive")
            XCTAssertFalse(message(turns * 2 + 2, role: "user").exists)
            for control in [draft, app.buttons["chat.attach.toggle"].firstMatch, app.buttons["chat.send"].firstMatch] {
                ready(control)
                XCTAssertFalse(control.frame.isEmpty)
                XCTAssertTrue(app.frame.contains(control.frame))
                XCTAssertLessThanOrEqual(control.frame.maxY, mikaUnobscuredBottom(in: app))
            }
        }
        phase("relaunch_preserved_archive") {
            app.terminate(); launch(reset: false)
            if expectsArchiveLimit {
                openHistory(lastIndex: 1999, marker: "LH-END-1000")
                XCTAssertFalse(message(2000, role: "user").exists, "The original full archive remains intact")
            } else {
                openHistory(lastIndex: 1999, marker: "測試回覆：" + probe)
                assertLabel(message(1998, role: "user"), probe)
            }
            XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
        }
        phase("reopened_earliest_navigation") { visitEarliest(total: 2000) }
        phase("reopened_latest_navigation") {
            visitLatest(lastIndex: 1999, marker: expectsArchiveLimit ? "LH-END-1000" : "測試回覆：" + probe)
        }
    }

    /// Run only after the 999 -> 1000 save/reopen assertions. Delete the synthetic
    /// provider through real Settings in this process: relaunching would reseed it.
    private func exerciseBlockedSendOnEarlierPage() {
        let blockedDraft = "Earlier page without model"
        phase("remove_fixture_provider") {
            navigateMikaSection("settings", in: app)
            openModelSettings(in: app)
            deleteModelProvider("model.example.invalid", in: app)
            returnFromModelSettings(in: app)
            navigateMikaSection("chat", in: app)
            assertLabel(app.staticTexts["chat.status"].firstMatch, "尚未設定模型")
            openHistory(lastIndex: 1999, marker: "測試回覆：" + probe)
        }
        phase("earlier_page_blocked_send") {
            visitEarliest(total: 2000)
            let draft = chatDraftControl(in: app)
            ready(draft); draft.tap(); prepareKeyboard()
            typeDraft(blockedDraft)
            tap("chat.dismissKeyboard")
            wait(NSPredicate(format: "exists == false"), on: app.keyboards.firstMatch, seconds: 10)
            let transcript = app.scrollViews["chat.transcript"].firstMatch
            // Reproduce the old-page hole, not the existing <200-point fallback.
            wait(NSPredicate { _, _ in
                transcript.exists && transcript.frame.height >= 200
            }, on: transcript, seconds: 10)
            let heightBeforeSend = transcript.frame.height
            XCTAssertGreaterThanOrEqual(heightBeforeSend, 200)
            tap("chat.send")
            let card = app.descendants(matching: .any)["chat.sendBlocked"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertTrue(card.staticTexts["還不能開始任務"].exists)
            XCTAssertTrue(card.staticTexts["還缺：還沒有能用的模型"].exists)
            XCTAssertFalse(transcript.descendants(matching: .any)["chat.sendBlocked"].exists,
                           "An earlier page needs the composer fallback, outside omitted tailRows")
            for identifier in ["chat.sendBlocked.dismiss", "chat.sendBlocked.openSettings"] {
                let action = app.buttons[identifier].firstMatch
                ready(action)
                XCTAssertFalse(action.frame.isEmpty)
                XCTAssertTrue(app.frame.contains(action.frame))
                XCTAssertLessThanOrEqual(action.frame.maxY, draft.frame.minY)
            }
            XCTAssertFalse(card.frame.isEmpty)
            XCTAssertTrue(app.frame.contains(card.frame))
            XCTAssertGreaterThanOrEqual(card.frame.minY, transcript.frame.maxY)
            XCTAssertEqual(draft.value as? String, blockedDraft)
            XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
            XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
            // An off-page absence check alone cannot prove no append: verify total
            // and unchanged old-page bounds, then inspect the latest page below.
            assertBoundedPage(first: 0, last: 79, total: 2000)
            XCTAssertFalse(app.buttons["chat.history.earliest"].firstMatch.isEnabled)
            print("LONG_HISTORY_BLOCKED_SEND total=2000 first=0 last=79 viewportBefore=\(heightBeforeSend) fallback=1")
            capture("long-history-earlier-page-no-model")
        }
        phase("blocked_send_settings_action") {
            tap("chat.sendBlocked.openSettings")
            XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
            ready(app.buttons["settings.modelJump"].firstMatch)
            navigateMikaSection("chat", in: app)
            assertLabel(app.staticTexts["chat.status"].firstMatch, "尚未設定模型")
            XCTAssertFalse(app.descendants(matching: .any)["chat.sendBlocked"].exists)
            XCTAssertEqual(chatDraftControl(in: app).value as? String, blockedDraft)
            // Returning from Settings may recreate ChatView already on the latest
            // page; otherwise explicitly leave the earlier page before checking IDs.
            if app.buttons["chat.history.latest"].firstMatch.isEnabled { tap("chat.history.latest") }
            assertLatest(lastIndex: 1999, marker: "測試回覆：" + probe)
            assertLabel(message(1998, role: "user"), probe)
            XCTAssertFalse(message(2000, role: "user").exists)
            XCTAssertFalse(message(2001, role: "assistant").exists)
            XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
        }
    }

    private func launch(reset: Bool) {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-WoowSkipOnboarding",
            "-UITestMode", "-UITestNamespace", namespace, "-UITestTranscriptFixture",
            "-UITestLongHistoryFixture", "-UITestLongHistoryTurns", String(initialTurns)]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
    }

    private func openHistory(lastIndex: Int, marker: String) {
        tap("chat.menu")
        let row = app.buttons["drawer.recent.row." + namespace].firstMatch
        ready(row)
        XCTAssertTrue(row.label.hasPrefix("LH-SYNTHETIC-\(initialTurns)"))
        row.tap()
        assertLatest(lastIndex: lastIndex, marker: marker)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
    }

    private func assertLatest(lastIndex: Int, marker: String) {
        let last = message(lastIndex, role: "assistant")
        wait(NSPredicate(format: "exists == true AND label CONTAINS %@", marker), on: last, seconds: 15)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        // A long last paragraph need not fit wholly; its bottom must be in the viewport.
        wait(NSPredicate { _, _ in
            last.exists && last.isHittable && !last.frame.isEmpty
                && last.frame.maxY > transcript.frame.minY
                && last.frame.maxY <= transcript.frame.maxY
        }, on: last, seconds: 10)
        assertBoundedPage(first: lastIndex + 1 - 80, last: lastIndex, total: lastIndex + 1)
    }

    private func visitEarliest(total: Int) {
        tap("chat.history.earliest")
        let first = message(0, role: "user")
        wait(NSPredicate(format: "exists == true AND label BEGINSWITH %@", "LH-SYNTHETIC-\(initialTurns) 第1輪"),
             on: first, seconds: 15)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        wait(NSPredicate { _, _ in
            first.exists && first.isHittable && !first.frame.isEmpty
                && first.frame.minY >= transcript.frame.minY
                && first.frame.minY < transcript.frame.maxY
        }, on: first, seconds: 10)
        XCTAssertTrue(message(79, role: "assistant").label.contains("LH-END-40"))
        assertBoundedPage(first: 0, last: 79, total: total)
        XCTAssertFalse(message(total - 1, role: "assistant").exists)
        XCTAssertFalse(app.buttons["chat.history.earliest"].firstMatch.isEnabled)
        XCTAssertFalse(app.buttons["chat.history.earlier"].firstMatch.isEnabled)
        XCTAssertTrue(app.buttons["chat.history.newer"].firstMatch.isEnabled)
    }

    private func visitLatest(lastIndex: Int, marker: String) {
        tap("chat.history.latest")
        assertLatest(lastIndex: lastIndex, marker: marker)
        XCTAssertFalse(message(0, role: "user").exists)
        XCTAssertFalse(app.buttons["chat.history.newer"].firstMatch.isEnabled)
    }

    private func assertBoundedPage(first: Int, last: Int, total: Int) {
        XCTAssertFalse(app.buttons["chat.returnToLatest"].exists,
                       "Paged history uses its top Latest control without covering replies")
        // The zh-Hant display locale groups thousands (native272: 1,919–1,998).
        // Keep exact label equality, including all three independently expected counts.
        let expectedRange = String(format: "第 %1$lld–%2$lld 則，共 %3$lld 則",
                                   locale: Locale(identifier: "zh-Hant"),
                                   arguments: [Int64(first + 1), Int64(last + 1), Int64(total)])
        assertLabel(app.staticTexts["chat.history.range"].firstMatch, expectedRange)
        // Query the actual exposed message nodes once per observation. A claimed
        // range alone cannot prove the other 1920 views/AX nodes were removed.
        let nodes = app.scrollViews["chat.transcript"].descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", #"^chat\.message\.[0-9]+\.(user|assistant)$"#))
        let count = nodes.count
        XCTAssertEqual(count, last - first + 1)
        XCTAssertLessThanOrEqual(count, 80)
        pageObservations.append(["firstIndex": first, "lastIndex": last, "totalMessages": total, "axMessageNodes": count])
        print("LONG_HISTORY_PAGE first=\(first) last=\(last) total=\(total) axMessageNodes=\(count)")
    }

    private func assertVisibleReply(_ reply: XCUIElement) {
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        wait(NSPredicate { _, _ in
            reply.exists && reply.isHittable && !reply.frame.isEmpty
                && transcript.frame.contains(reply.frame)
                && reply.frame.maxY <= mikaUnobscuredBottom(in: self.app)
        }, on: reply, seconds: 10)
    }

    private func typeDraft(_ text: String) {
        let draft = chatDraftControl(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        draft.typeText(text)
        XCTAssertEqual(draft.value as? String, text)
    }

    private func prepareKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissKeyboardIntroduction()
        func latin() -> Bool {
            app.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && app.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
        ready(globe); globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap(); dismissKeyboardIntroduction()
        wait(NSPredicate { _, _ in latin() }, on: app.keyboards.firstMatch, seconds: 10)
    }

    private func dismissKeyboardIntroduction() {
        let button = app.buttons["Continue"].firstMatch
        if button.waitForExistence(timeout: 3) { ready(button); button.tap() }
    }

    private func message(_ index: Int, role: String) -> XCUIElement {
        app.descendants(matching: .any)["chat.message.\(index).\(role)"].firstMatch
    }

    private func tap(_ identifier: String) {
        let control = app.buttons[identifier].firstMatch
        ready(control); control.tap()
    }

    private func ready(_ element: XCUIElement) {
        wait(NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), on: element, seconds: 10)
    }

    private func assertLabel(_ element: XCUIElement, _ value: String) {
        wait(NSPredicate(format: "exists == true AND label == %@", value), on: element, seconds: 15)
        XCTAssertEqual(element.label, value)
    }

    private func wait(_ predicate: NSPredicate, on element: XCUIElement, seconds: TimeInterval) {
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                         timeout: seconds), .completed)
        }
    }

    private func phase(_ name: String, _ action: () -> Void) {
        activePhase = name
        let started = ProcessInfo.processInfo.systemUptime
        phaseStarted = started
        print("LONG_HISTORY_PHASE_BEGIN name=\(name) turns=\(initialTurns) uptime=\(started)")
        XCTContext.runActivity(named: "long-history \(initialTurns): \(name)") { _ in action() }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        timings.append(["phase": name, "seconds": elapsed, "failureCount": testRun?.failureCount ?? 0])
        print("LONG_HISTORY_PHASE_END name=\(name) turns=\(initialTurns) seconds=\(elapsed)")
        activePhase = nil
        phaseStarted = nil
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
