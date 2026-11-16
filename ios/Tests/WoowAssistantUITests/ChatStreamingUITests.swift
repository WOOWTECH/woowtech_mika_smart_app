import XCTest

/// Native controls, actual ChatSession/archive/notification adapter. The explicit
/// DEBUG model fixture supplies only two bounded text deltas, never stored data.
final class ChatStreamingUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    // ui-chat permits 300 s. On the iOS 26.2 runner each UI step costs 1–2 s and the
    // shared model setup alone took about 170 s, leaving these streaming cases at
    // 231–240 s; one setup-heavy case ran out before its first send.
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 300 }
    override func tearDownWithError() throws { app.terminate() }

    /// Exercises the actual composer state with a cancellable fake transport.
    /// The field and microphone are disabled during generation: no steer/answer
    /// placeholder can truthfully imply that an interrupt would be accepted.
    /// One case per system language: the three together took up to 290 s on
    /// iPhone SE and ran past the 300 s ui-chat maximum on iPhone 16 Pro Max.
    func testComposerIdleAndBusyControlsForTraditionalChineseSystem() {
        assertComposerIdleAndBusyControls(systemLanguages: "(zh-Hant)", placeholder: "輸入訊息", voiceLabel: "語音輸入",
                                          stopped: "已停止。")
    }

    /// A Simplified Chinese system shows Traditional Chinese.
    func testComposerIdleAndBusyControlsForSimplifiedChineseSystem() {
        assertComposerIdleAndBusyControls(systemLanguages: "(zh-Hans)", placeholder: "輸入訊息", voiceLabel: "語音輸入",
                                          stopped: "已停止。")
    }

    func testComposerIdleAndBusyControlsForEnglishSystem() {
        assertComposerIdleAndBusyControls(systemLanguages: "(en)", placeholder: "Type a message", voiceLabel: "Voice input",
                                          stopped: "Stopped.")
    }

    private func assertComposerIdleAndBusyControls(systemLanguages: String, placeholder: String, voiceLabel: String,
                                                   stopped: String) {
        launch(); configure(); disableMemory()
        launchLocalizedStreamingFixture(app, systemLanguages: systemLanguages, namespace: namespace)
        let draft = chatDraftControl(in: app)
        let mic = app.buttons["chat.voice"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 15))
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        wait(NSPredicate(format: "placeholderValue == %@", placeholder), on: draft)
        XCTAssertTrue(draft.isEnabled)
        XCTAssertEqual(mic.label, voiceLabel)
        XCTAssertTrue(mic.isEnabled)
        XCTAssertFalse(app.buttons["chat.cancel"].exists)
        compose("[fixture:stream-cancel]"); tap("chat.send")
        // Like the Play build the question shows at once and the input bar empties.
        assertLabel(identifiedText("chat.message.0.user"), "[fixture:stream-cancel]")
        assertLabel(app.staticTexts["chat.partialReply"].firstMatch, "串流測試：第一段")
        XCTAssertFalse(draft.isEnabled, "Generating does not accept typed interrupts")
        XCTAssertFalse(mic.isEnabled, "Generating does not accept voice interrupts")
        XCTAssertTrue(app.buttons["chat.cancel"].isEnabled)
        tap("chat.cancel")
        assertLabel(identifiedText("chat.message.1.assistant"), stopped)
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
        wait(NSPredicate(format: "enabled == true"), on: draft)
        wait(NSPredicate(format: "enabled == true"), on: mic)
        XCTAssertNotEqual(draft.value as? String, "[fixture:stream-cancel]")
    }

    func testMemoryEnabledStructuredStreamPreviewsThenArchivesCompletedAnswer() {
        launch(); configure()
        navigate("memory")
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app); ready(toggle)
        XCTAssertEqual(toggle.value as? String, "1", "Exercise the memory-enabled structured path")
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        navigate("chat")

        compose("[fixture:structured-stream-complete]"); tap("chat.send")
        assertLabel(identifiedText("chat.message.0.user"), "[fixture:structured-stream-complete]")
        assertLabel(identifiedText("chat.partialReply"), "結構化串流：第一段")
        XCTAssertFalse(identifiedText("chat.message.1.assistant").exists)
        assertLabel(app.staticTexts["chat.status"].firstMatch, "正在處理")
        assertArchiveUnavailableDuringRun()

        let completed = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label == %@", "結構化串流：第一段；完整回覆。"), on: completed, seconds: 35)
        XCTAssertFalse(identifiedText("chat.partialReply").exists)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
        launch(reset: false); openArchive()
        let saved = row("[fixture:structured-stream-complete]")
        ready(saved); saved.tap()
        assertLabel(identifiedText("chat.message.1.assistant"), "結構化串流：第一段；完整回覆。")
        print("STRUCTURED_STREAM_UI memoryEnabled=1 partialObserved=1 archiveAfterCompletion=1 archiveRelaunch=1")
    }

    func testPartialBecomesCompletedReplyAndDurableArchive() {
        launch(); configure(); disableMemory(); enableNotifications()
        let draft = chatDraftControl(in: app)
        wait(NSPredicate(format: "placeholderValue == %@", "輸入訊息"), on: draft)
        assertNotificationAttempts(0)
        compose("[fixture:stream-complete]"); tap("chat.send")
        assertLabel(identifiedText("chat.message.0.user"), "[fixture:stream-complete]")
        assertLabel(app.staticTexts["chat.partialReply"].firstMatch, "串流測試：第一段")
        XCTAssertFalse(identifiedText("chat.message.1.assistant").exists)
        assertArchiveUnavailableDuringRun()
        assertNotificationAttempts(0)
        let completed = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label == %@", "串流測試：第一段；完整回覆。"), on: completed, seconds: 35)
        XCTAssertEqual(completed.label, "串流測試：第一段；完整回覆。")
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
        XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
        XCTAssertNotEqual(draft.value as? String, "[fixture:stream-complete]")
        wait(NSPredicate(format: "placeholderValue == %@", "繼續說點什麼…"), on: draft)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
        assertNotificationAttempts(1)
        launch(reset: false); openArchive()
        let saved = row("[fixture:stream-complete]"); ready(saved); saved.tap()
        assertLabel(identifiedText("chat.message.1.assistant"), "串流測試：第一段；完整回覆。")
        print("CHAT_STREAM_UI partialObserved=1 completedPair=1 archiveRelaunch=1 completionNotificationAttempts=1")
    }

    /// Like the Play build a stop leaves the question with 已停止。, saved with the
    /// conversation; the partial is not kept and nothing notifies a completion.
    func testCancelLeavesStoppedTurnSavedWithoutPartialOrCompletionNotification() {
        launch(); configure(); disableMemory(); enableNotifications()
        assertNotificationAttempts(0)
        compose("[fixture:stream-cancel]"); tap("chat.send")
        assertLabel(identifiedText("chat.message.0.user"), "[fixture:stream-cancel]")
        assertLabel(app.staticTexts["chat.partialReply"].firstMatch, "串流測試：第一段")
        tap("chat.cancel")
        assertLabel(identifiedText("chat.message.1.assistant"), "已停止。")
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
        XCTAssertNotEqual(chatDraftControl(in: app).value as? String, "[fixture:stream-cancel]")
        assertNotificationAttempts(0)
        launch(reset: false)
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists, "Partials are not claimed durable")
        openArchive()
        let saved = row("[fixture:stream-cancel]"); ready(saved); saved.tap()
        assertLabel(identifiedText("chat.message.0.user"), "[fixture:stream-cancel]")
        assertLabel(identifiedText("chat.message.1.assistant"), "已停止。")
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
        print("CHAT_STREAM_UI partialObserved=1 cancelled=1 stoppedTurnSaved=1 completionNotificationAttempts=0")
    }

    func testMarkdownFormatsCompletedBubbleButArchivesOriginalStreamingBytes() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-markdown]"); tap("chat.send")
        let partial = identifiedText("chat.partialReply")
        wait(NSPredicate(format: "label CONTAINS %@", "**粗體"), on: partial, seconds: 10)
        XCTAssertTrue(partial.label.contains("標題"))
        XCTAssertFalse(identifiedText("chat.message.1.assistant").exists)

        let completed = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label CONTAINS %@", "• 第二項"), on: completed, seconds: 35)
        XCTAssertTrue(completed.label.contains("粗體 與 連結"))
        XCTAssertTrue(completed.label.contains("• 第一項"))
        XCTAssertFalse(completed.label.contains("**") || completed.label.contains("[連結]"))
        XCTAssertFalse(identifiedText("chat.partialReply").exists)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)

        launch(reset: false); openArchive()
        let saved = row("[fixture:stream-markdown]"); ready(saved); saved.tap()
        // Like Play there is no history sheet showing the stored source; reopening the
        // chat from the drawer renders the archived Markdown into the same bubble.
        let reopened = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label CONTAINS %@", "• 第二項"), on: reopened, seconds: 10)
        XCTAssertTrue(reopened.label.contains("標題") && reopened.label.contains("粗體 與 連結"))
        XCTAssertTrue(reopened.label.contains("• 第一項"))
        XCTAssertFalse(reopened.label.contains("**") || reopened.label.contains("[連結]"))
    }

    func testReadingEarlierStreamingTextDoesNotJumpToNewChunk() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-scroll]"); tap("chat.send")
        let partial = identifiedText("chat.partialReply")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_FIRST_END"), on: partial, seconds: 12)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        ready(transcript)
        let bottomOrigin = partial.frame.minY
        for _ in 0..<3 where partial.frame.minY - bottomOrigin <= 260 { transcript.swipeDown() }
        let readingOrigin = partial.frame.minY
        XCTAssertGreaterThan(readingOrigin - bottomOrigin, 260, "Native scrolling must reach earlier transcript text")
        XCTAssertFalse(partial.label.contains("SCROLL_SECOND_END"), "Observe an actual later delta after the native scroll")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_SECOND_END"), on: partial, seconds: 65)
        XCTAssertLessThan(abs(partial.frame.minY - readingOrigin), 32,
                          "A later real stream delta must not pull a reader back to the tail")
        let completed = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_SECOND_END"), on: completed, seconds: 55)
        XCTAssertGreaterThan(completed.frame.minY, readingOrigin - 160,
                             "Completion must not treat the first saved message as a new conversation and jump to the tail")
        XCTAssertFalse(partial.exists)
    }

    /// Split from the case above: on iPhone SE (iOS 18.5) the two together need
    /// more than the 240 s allowance, mostly fixed fixture waits and typing.
    /// Like the Play build the sent question appears at once; the transcript
    /// follows it, the reply and the 已停止。 that ends it at the tail.
    func testSendAfterReadingEarlierTextFollowsTheNewAnswer() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-scroll]"); tap("chat.send")
        let completed = identifiedText("chat.message.1.assistant")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_SECOND_END"), on: completed, seconds: 100)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        ready(transcript)
        let tailOrigin = completed.frame.minY
        for _ in 0..<3 where completed.frame.minY - tailOrigin <= 260 { transcript.swipeDown() }
        XCTAssertGreaterThan(completed.frame.minY - tailOrigin, 260, "Native scrolling must reach earlier transcript text")

        // Editing the next prompt changes the keyboard/viewport; the explicit
        // send must nevertheless restore follow for the accepted new request.
        compose("[fixture:stream-cancel]"); tap("chat.send")
        assertLabel(identifiedText("chat.message.2.user"), "[fixture:stream-cancel]")
        let renewed = identifiedText("chat.partialReply")
        assertLabel(renewed, "串流測試：第一段")
        XCTAssertTrue(renewed.isHittable, "The newly submitted answer must be visible at the tail")
        assertTranscriptTailVisible(renewed, in: transcript)
        XCTAssertFalse(app.buttons["chat.returnToLatest"].firstMatch.exists, "Sending returns the reader to the tail")
        tap("chat.cancel")
        let stopped = identifiedText("chat.message.3.assistant")
        assertLabel(stopped, "已停止。")
        assertTranscriptTailVisible(stopped, in: transcript)
    }

    func testSmallScrollAndLongPressDoNotJumpWhenLaterChunkArrives() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-scroll]"); tap("chat.send")
        let partial = identifiedText("chat.partialReply")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_FIRST_END"), on: partial, seconds: 12)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        ready(transcript)
        let bottomOrigin = partial.frame.minY
        let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let readingOrigin = partial.frame.minY
        XCTAssertGreaterThanOrEqual(readingOrigin - bottomOrigin, 100,
                                    "The native gesture must intentionally scroll at least 100 points above the tail")
        XCTAssertLessThanOrEqual(readingOrigin - bottomOrigin, 200,
                                 "This case must exercise a small 100–200 point scroll, not a distant reading position")

        // Touch the visible part of the selectable Text, rather than the
        // center of its very tall AX frame, which can lie off screen.
        let visibleText = partial.frame.intersection(transcript.frame)
        XCTAssertFalse(visibleText.isNull)
        XCTAssertGreaterThan(visibleText.height, 40)
        let origin = transcript.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: visibleText.midX - transcript.frame.minX,
                                   dy: visibleText.midY - transcript.frame.minY)).press(forDuration: 1)
        let selectionLabel = NSPredicate(format: "label IN %@",
                                         ["Copy", "複製", "复制", "拷貝", "Select All", "全選", "全选"])
        func selectionAction() -> XCUIElement? {
            let menu = app.menuItems.matching(selectionLabel).firstMatch
            if menu.exists && menu.isHittable { return menu }
            let button = app.buttons.matching(selectionLabel).firstMatch
            return button.exists && button.isHittable ? button : nil
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in selectionAction() != nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "A stationary long press must still expose native text-selection actions")
        XCTAssertFalse(partial.label.contains("SCROLL_SECOND_END"),
                       "Selection must be active before the later real stream delta")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_SECOND_END"), on: partial, seconds: 65)
        XCTAssertLessThan(abs(partial.frame.minY - readingOrigin), 32,
                          "A real later delta must not move the small-scroll reader during native text selection")
        let updatedVisibleText = partial.frame.intersection(transcript.frame)
        XCTAssertFalse(updatedVisibleText.isNull)
        XCTAssertGreaterThan(updatedVisibleText.height, 40)
        // The update may dismiss the native edit menu while keeping the text
        // selected. Tap that visible selection once to request the menu again;
        // do not reselect or repeat the long press to manufacture a pass.
        if selectionAction() == nil {
            origin.withOffset(CGVector(dx: updatedVisibleText.midX - transcript.frame.minX,
                                       dy: updatedVisibleText.midY - transcript.frame.minY)).tap()
        }
        let afterUpdate = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in selectionAction() != nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [afterUpdate], timeout: 5), .completed,
                       "The updated real streaming text must still expose native selection actions")
    }

    func testNoOpDragAtBottomStillFollowsLaterGrowth() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-noop]"); tap("chat.send")
        let partial = identifiedText("chat.partialReply")
        wait(NSPredicate(format: "label == %@", "短回覆；等待下一段。"), on: partial, seconds: 12)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        ready(transcript)
        let originY = partial.frame.minY
        let start = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 150)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        let bouncedBack = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            partial.exists && abs(partial.frame.minY - originY) < 12
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [bouncedBack], timeout: 8), .completed,
                       "The bottom drag must finish without real content displacement")
        wait(NSPredicate(format: "label CONTAINS %@", "SCROLL_NOOP_GROW_END"), on: partial, seconds: 50)
        XCTAssertFalse(app.buttons["chat.returnToLatest"].firstMatch.exists,
                       "A no-op drag cannot leave the reader stuck above new text")
        assertTranscriptTailVisible(partial, in: transcript)
    }

    func testReturningToBottomByDragOrButtonResumesLaterFragments() {
        launch(); configure(); disableMemory()
        compose("[fixture:stream-return]"); tap("chat.send")
        let partial = identifiedText("chat.partialReply")
        wait(NSPredicate(format: "label CONTAINS %@", "RETURN_FIRST_END"), on: partial, seconds: 12)
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        ready(transcript)
        let returnButton = app.buttons["chat.returnToLatest"].firstMatch
        swipeEarlierOnce(partial, in: transcript, returnButton: returnButton)
        ready(returnButton)
        XCTAssertFalse(partial.label.contains("RETURN_SECOND_END"),
                       "Reader must return before the next actual fragment")
        for _ in 0..<3 where returnButton.exists { transcript.swipeUp() }
        assertGone(returnButton, seconds: 8)
        wait(NSPredicate(format: "label CONTAINS %@", "RETURN_SECOND_END"), on: partial, seconds: 50)
        assertTranscriptTailVisible(partial, in: transcript)

        swipeEarlierOnce(partial, in: transcript, returnButton: returnButton)
        ready(returnButton)
        XCTAssertFalse(partial.label.contains("RETURN_THIRD_END"),
                       "The explicit return must precede the third actual fragment")
        returnButton.tap()
        assertGone(returnButton, seconds: 5)
        wait(NSPredicate(format: "label CONTAINS %@", "RETURN_THIRD_END"), on: partial, seconds: 50)
        assertTranscriptTailVisible(partial, in: transcript)
    }

    private func swipeEarlierOnce(_ text: XCUIElement, in transcript: XCUIElement, returnButton: XCUIElement) {
        let viewport = transcript.frame
        let before = text.frame
        let beforeLabel = text.label
        XCTAssertFalse(viewport.isEmpty)
        XCTAssertFalse(before.isEmpty)
        // The selectable Text fills the viewport on iPad, so its AX frame
        // cannot identify a blank gutter. Use the native ScrollView swipe,
        // as in the earlier-reading test, without a stationary selection press.
        transcript.swipeDown()
        let displaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            text.exists && text.frame.minY - before.minY >= 24
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [displaced], timeout: 5), .completed,
                       "One native swipe must move the real transcript toward earlier text")
        ready(returnButton)
        XCTAssertEqual(text.label, beforeLabel, "Displacement must precede the next stream fragment")
        XCTAssertLessThan(abs(transcript.frame.minY - viewport.minY), 1,
                          "The transcript viewport must not move during the swipe")
        XCTAssertLessThan(abs(transcript.frame.height - viewport.height), 1,
                          "The transcript viewport must not resize during the swipe")
        XCTAssertGreaterThanOrEqual(text.frame.minY - before.minY, 24,
                                    "The displacement must remain after the return button appears")
    }

    private func assertTranscriptTailVisible(_ text: XCUIElement, in transcript: XCUIElement) {
        let atTail = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            text.exists && abs(text.frame.maxY - transcript.frame.maxY) < 65
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [atTail], timeout: 10), .completed,
                       "The real later fragment must remain visible at the transcript tail")
        XCTAssertLessThan(abs(text.frame.maxY - transcript.frame.maxY), 65)
    }

    private func assertGone(_ element: XCUIElement, seconds: TimeInterval) {
        let gone = NSPredicate(format: "exists == false")
        if !gone.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)],
                                         timeout: seconds), .completed)
        }
        XCTAssertFalse(element.exists)
    }

    private func disableMemory() {
        navigate("memory")
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app); ready(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        // SwiftUI can expose the labelled row as an outer Switch. Target the
        // actual native child when present, as the existing Memory drivers do.
        let native = toggle.switches.firstMatch
        let target = native.exists ? native : toggle
        ready(target)
        XCTAssertTrue(app.frame.contains(target.frame)); XCTAssertFalse(target.frame.isEmpty)
        // iOS 18 reports the native switch outside the row-wide AX wrapper's
        // frame. Its own visible, hittable frame and the observed value change
        // establish that the identified control was actually switched.
        XCTAssertTrue(target.isHittable)
        XCTAssertLessThanOrEqual(target.frame.maxY, mikaUnobscuredBottom(in: app))
        print("CHAT_STREAM_UI memorySwitchNativeChild=\(native.exists ? 1 : 0) initialValue=1")
        target.tap()
        wait(NSPredicate(format: "value == %@", "0"), on: toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        navigate("chat")
    }
    private func enableNotifications() {
        navigate("settings"); tap("settings.notifications", scroll: true)
        let authorization = app.staticTexts["notifications.authorization"].firstMatch
        revealLearningElement(authorization, in: app, visibility: .readableText)
        wait(NSPredicate(format: "value IN %@", ["notDetermined", "authorized"]), on: authorization)
        let before = authorization.value as? String
        XCTAssertTrue(before == "notDetermined" || before == "authorized", "No simulator permission resets")
        // 去開啟 on Play's 通知總開關, the row that is a button while off.
        tap("notifications.enabled", scroll: true)
        if before == "notDetermined" {
            let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 15))
            let text = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
            XCTAssertTrue(text.contains("渥屋助理") || text.contains("WoowAssistant"))
            XCTAssertTrue(text.contains("通知") || text.localizedCaseInsensitiveContains("notifications"))
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允許", "允许"])).firstMatch
            ready(allow); allow.tap()
        }
        revealLearningElement(authorization, in: app, visibility: .readableText)
        wait(NSPredicate(format: "value == %@", "authorized"), on: authorization, seconds: 15)
        let master = app.descendants(matching: .any)["notifications.enabled"].firstMatch
        wait(NSPredicate(format: "value == %@", "已允許"), on: master, seconds: 15)
        let back = app.navigationBars["通知"].buttons.firstMatch; ready(back); back.tap()
        navigate("chat")
    }
    private func assertNotificationAttempts(_ expected: Int) {
        let observation = app.staticTexts["stream.fixture.notifications"].firstMatch
        wait(NSPredicate(format: "value == %@", String(expected)), on: observation)
        XCTAssertEqual(observation.value as? String, String(expected), "Actual OS adapter add attempts, not transient banner absence")
    }
    private func wait(_ predicate: NSPredicate, on element: XCUIElement, seconds: TimeInterval = 10) {
        if !element.exists || !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: seconds), .completed)
        }
        XCTAssertTrue(element.exists)
    }
    private func launch(reset: Bool = true) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", namespace, "-UITestChatStreaming", "-WoowSkipOnboarding"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]; app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
        if !reset { assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定") }
    }
    private func configure() {
        navigate("settings")
        openModelSettings(in: app)
        write("https://model.invalid/v1", field: app.textFields["settings.baseURL"].firstMatch, scroll: true)
        // On SE, the URL keyboard covers settings.model. Finish editing through
        // the real keyboard toolbar before requiring that next field to be
        // fully visible; do not scroll or tap through an obscured control.
        dismissSettingsKeyboard()
        write("fixture", field: app.textFields["settings.model"].firstMatch,
              scroll: true, verifyEachCharacter: true)
        dismissSettingsKeyboard()
        let key = app.secureTextFields["settings.apiKey"].firstMatch
        revealLearningElement(key, in: app); ready(key); key.tap(); prepareKeyboard(); key.typeText("fixture-key")
        tap("settings.dismissKeyboard"); tap("setup.test", scroll: true)
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app)
        navigate("chat"); assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }
    private func dismissSettingsKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        tap("settings.dismissKeyboard")
        let keyboardAbsent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardAbsent], timeout: 5), .completed)
    }
    private func compose(_ text: String) {
        let draft = chatDraftControl(in: app)
        write(text, field: draft, scroll: false); tap("chat.dismissKeyboard")
        XCTAssertEqual(draft.value as? String, text)
    }
    private func send(_ text: String) {
        compose(text); tap("chat.send")
        assertLabel(identifiedText("chat.message.1.assistant"), "測試回覆：" + text)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
    }
    private func row(_ title: String) -> XCUIElement {
        let scroll = app.scrollViews["drawer.scroll"].firstMatch
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                      "drawer.recent.row.", title)).firstMatch
        for _ in 0..<4 where !target.exists || !scroll.frame.contains(target.frame) { scroll.swipeUp() }
        return target
    }
    private func identifiedText(_ identifier: String) -> XCUIElement {
        // Selectable SwiftUI Text can be an AX Other on iOS 17 and StaticText
        // on newer runtimes. Keep the exact identifier and label assertions.
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func navigate(_ section: String) {
        navigateMikaSection(section, in: app)
        XCTAssertTrue(app.staticTexts[section + ".status"].firstMatch.waitForExistence(timeout: 5))
    }
    private func write(_ text: String, field: XCUIElement, scroll: Bool,
                       verifyEachCharacter: Bool = false) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field)
        if !scroll {
            XCTAssertTrue(app.frame.contains(field.frame)); XCTAssertFalse(field.frame.isEmpty)
            XCTAssertLessThanOrEqual(field.frame.maxY, mikaUnobscuredBottom(in: app))
        }
        field.tap(); prepareKeyboard()
        var entered = "", remaining = text[...]
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(verifyEachCharacter ? 1 : (entered.isEmpty ? 1 : 16)))
            field.typeText(chunk); entered += chunk; remaining = remaining.dropFirst(chunk.count)
            if verifyEachCharacter {
                let prefix = NSPredicate(format: "value == %@", entered)
                if !prefix.evaluate(with: field) {
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: prefix, object: field)],
                                                 timeout: 3), .completed,
                                   "Each native model-name character must reach the actual field before the next")
                }
            }
            XCTAssertEqual(field.value as? String, entered, "Native text must be exact without repair or retry")
            guard field.value as? String == entered else { return }
        }
    }
    private func prepareKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); dismissIntroduction()
        let keyboard = app.keyboards.firstMatch
        func latin() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        // ccfd SE AX labels this native control 下一個鍵盤 (identifier emoji).
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤", "下一个键盘"])).firstMatch
        ready(globe); globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap(); dismissIntroduction()
        if !latin() { XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latin() }, object: nil)], timeout: 10), .completed) }
    }
    private func dismissIntroduction() {
        let button = app.buttons["Continue"].firstMatch
        guard button.waitForExistence(timeout: 3) else { return }
        XCTAssertTrue(app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."].firstMatch.exists)
        ready(button); button.tap()
        let absent = NSPredicate(format: "exists == false")
        if !absent.evaluate(with: button) { XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: button)], timeout: 5), .completed) }
    }
    /// Like the Play build, saved chats are listed in the drawer (no history sheet).
    private func openArchive() {
        tap("chat.menu")
        XCTAssertTrue(app.scrollViews["drawer.scroll"].firstMatch.waitForExistence(timeout: 10))
    }
    private func assertArchiveUnavailableDuringRun() {
        tap("chat.menu")
        let newConversation = app.buttons["drawer.newConversation"].firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 5))
        XCTAssertFalse(newConversation.isEnabled, "Switching chats waits until the run ends")
        tap("drawer.close")
    }
    private func tap(_ id: String, scroll: Bool = false) {
        let button = app.buttons[id].firstMatch
        if scroll { revealLearningElement(button, in: app) }
        ready(button); XCTAssertTrue(app.frame.contains(button.frame)); button.tap()
    }
    private func ready(_ element: XCUIElement) {
        let hittable = NSPredicate(format: "hittable == true")
        if !hittable.evaluate(with: element) { XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: element)], timeout: 10), .completed) }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isEnabled)
    }
    private func assertLabel(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "exists == true AND label == %@", value)
        if !predicate.evaluate(with: element) { XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed) }
        XCTAssertEqual(element.label, value)
    }
}
