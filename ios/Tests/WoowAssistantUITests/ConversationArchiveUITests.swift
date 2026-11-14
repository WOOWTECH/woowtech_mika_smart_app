import CoreGraphics
import XCTest

/// Native interaction with the real encrypted archive. Only model replies use
/// the existing isolated UI fixture; no archive rows are seeded by the test.
final class ConversationArchiveUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString

    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    func testTwoCompletedConversationsSurviveRelaunchAndOpenExplicitly() {
        launch(); configure()
        send("Archive first"); tap("chat.newConversation")
        send("Archive second")
        launch(reset: false)
        XCTAssertFalse(app.staticTexts["chat.message.0.user"].firstMatch.exists, "No active conversation autoload")
        // Like the Play build, the drawer lists every saved chat; there is no history sheet.
        tap("chat.menu")
        XCTAssertTrue(revealRecentRow("Archive second").exists)
        let first = revealRecentRow("Archive first")
        ready(first); first.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Archive first")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：Archive first")
        XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.profileReceipt"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.memoryReceipt"].firstMatch.exists)
    }

    func testDrawerRecentRowsComeFromSavedArchiveAndOpenWithoutRestartingWork() {
        launch(); configure()
        send("Recent first"); tap("chat.newConversation")
        send("Recent second")
        tap("chat.menu")
        let current = revealRecentRow("Recent second")
        XCTAssertEqual(current.value as? String, "目前對話")
        ready(current); current.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Recent second")
        XCTAssertFalse(app.descendants(matching: .any)["drawer.panel"].firstMatch.exists)

        launch(reset: false)
        XCTAssertFalse(app.staticTexts["chat.message.0.user"].firstMatch.exists, "History is never autoloaded")
        tap("chat.menu")
        let saved = revealRecentRow("Recent first")
        ready(saved); saved.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Recent first")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：Recent first")
        XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.profileReceipt"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.memoryReceipt"].firstMatch.exists)
    }

    func testDrawerRenameSurvivesRelaunchWithoutChangingSavedTurns() {
        launch(); configure(); send("A")
        tap("chat.menu")
        let original = revealRecentRow("A")
        ready(original); original.press(forDuration: 1)
        let rename = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "drawer.recent.rename.")).firstMatch
        ready(rename); rename.tap()
        let field = app.textFields["drawer.rename.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "A")
        ready(field); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("B")
        XCTAssertEqual(field.value as? String, "AB")
        tap("drawer.rename.save")
        let renamed = revealRecentRow("AB")
        XCTAssertEqual(renamed.label, "AB")
        ready(renamed); renamed.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "A")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：A")
        launch(reset: false)
        tap("chat.menu")
        XCTAssertEqual(revealRecentRow("AB").label, "AB")
        XCTAssertFalse(recentRow("A").exists)
    }

    func testDrawerRenameCancellationKeepsOriginalArchive() {
        launch(); configure(); send("A")
        tap("chat.menu")
        let original = revealRecentRow("A")
        ready(original); original.press(forDuration: 1)
        let rename = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "drawer.recent.rename.")).firstMatch
        ready(rename); rename.tap()
        let field = app.textFields["drawer.rename.field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "A")
        ready(field); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("B")
        XCTAssertEqual(field.value as? String, "AB")
        tap("drawer.rename.cancel")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: field)], timeout: 5), .completed)
        XCTAssertEqual(revealRecentRow("A").label, "A")
        XCTAssertFalse(recentRow("AB").exists)
        launch(reset: false)
        tap("chat.menu")
        XCTAssertEqual(revealRecentRow("A").label, "A")
        XCTAssertFalse(recentRow("AB").exists)
    }

    func testDrawerPinAndUnpinSurviveRelaunchWithoutChangingSavedTurns() {
        // On iPhone SE (iOS 18.5) the first context-menu press waits 60 s for an
        // "animations complete" notice that never arrives; ui-archive allows 300 s.
        executionTimeAllowance = 300
        launch(); configure(); send("Older")
        tap("chat.newConversation"); send("Newer")
        tap("chat.menu")
        let older = revealRecentRow("Older")
        let olderIdentifier = older.identifier
        let rowPrefix = "drawer.recent.row."
        XCTAssertTrue(olderIdentifier.hasPrefix(rowPrefix))
        let olderUUID = String(olderIdentifier.dropFirst(rowPrefix.count))
        XCTAssertNotNil(UUID(uuidString: olderUUID))
        let pinActionIdentifier = "drawer.recent.togglePin." + olderUUID
        ready(older); older.press(forDuration: 1)
        let pin = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            pinActionIdentifier, "置頂")).firstMatch
        ready(pin); pin.tap()
        XCTAssertTrue(app.staticTexts["drawer.pinned.title"].firstMatch.waitForExistence(timeout: 5))
        let livePinned = assertRecentRowValue("Older", identifier: olderIdentifier, value: "已置頂")
        XCTAssertEqual(revealRecentRow("Newer").value as? String, "目前對話")
        ready(livePinned); livePinned.press(forDuration: 1)
        let liveUnpin = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            pinActionIdentifier, "取消置頂")).firstMatch
        ready(liveUnpin)

        launch(reset: false); tap("chat.menu")
        XCTAssertTrue(app.staticTexts["drawer.pinned.title"].firstMatch.exists)
        let pinned = assertRecentRowValue("Older", identifier: olderIdentifier, value: "已置頂")
        ready(pinned); pinned.press(forDuration: 1)
        let unpin = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == %@",
            pinActionIdentifier, "取消置頂")).firstMatch
        ready(unpin); unpin.tap()
        let pinnedHeading = app.staticTexts["drawer.pinned.title"].firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: pinnedHeading)], timeout: 5), .completed)
        assertRecentRowValue("Older", identifier: olderIdentifier, value: "")
        let olderRow = revealRecentRow("Older")
        ready(olderRow); olderRow.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Older")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：Older")
        launch(reset: false); tap("chat.menu")
        XCTAssertFalse(app.staticTexts["drawer.pinned.title"].firstMatch.exists)
        assertRecentRowValue("Older", identifier: olderIdentifier, value: "")
        XCTAssertTrue(recentRow("Newer").exists)
    }

    func testDrawerPinMenuCancellationKeepsOriginalHistory() {
        launch(); configure(); send("Cancel pin")
        tap("chat.menu")
        let original = revealRecentRow("Cancel pin")
        ready(original); original.press(forDuration: 1)
        let pin = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@",
            "drawer.recent.togglePin.", "置頂")).firstMatch
        let rename = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "drawer.recent.rename.")).firstMatch
        ready(pin); ready(rename)
        let corners = [CGVector(dx: 0.05, dy: 0.15), CGVector(dx: 0.95, dy: 0.15),
                       CGVector(dx: 0.05, dy: 0.85), CGVector(dx: 0.95, dy: 0.85)]
        guard let outside = corners.first(where: { vector in
            let point = CGPoint(x: app.frame.minX + vector.dx * app.frame.width,
                                y: app.frame.minY + vector.dy * app.frame.height)
            return !pin.frame.contains(point) && !rename.frame.contains(point)
                && !original.frame.contains(point)
        }) else { XCTFail("No safe point outside the native menu"); return }
        app.coordinate(withNormalizedOffset: outside).tap()
        launch(reset: false); tap("chat.menu")
        XCTAssertFalse(app.staticTexts["drawer.pinned.title"].firstMatch.exists)
        XCTAssertEqual(revealRecentRow("Cancel pin").value as? String, "")
        let saved = revealRecentRow("Cancel pin")
        ready(saved); saved.tap()
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Cancel pin")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：Cancel pin")
    }

    func testDrawerRecentSwitchKeepsDraft() {
        launch(); configure(); send("Recent guarded")
        compose("Keep this unsent draft")
        tap("chat.menu")
        let current = revealRecentRow("Recent guarded")
        ready(current); XCTAssertEqual(current.value as? String, "目前對話")
        current.tap()
        XCTAssertEqual(app.descendants(matching: .any)["chat.draft"].firstMatch.value as? String, "Keep this unsent draft")
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Recent guarded")

        tap("chat.newConversation"); tap("chat.menu")
        let saved = revealRecentRow("Recent guarded")
        XCTAssertFalse(saved.isEnabled, "Existing unsent draft blocks the shortcut")
        XCTAssertEqual(saved.value as? String, "草稿或附件未送出，請先返回處理。")
    }

    func testNewConversationKeepsOrdinaryTextDraftFromBothControls() {
        launch(); configure(); compose("Keep ordinary unsent text")
        tap("chat.newConversation")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any)["chat.draft"].firstMatch.value as? String,
                       "Keep ordinary unsent text")
        tap("chat.menu"); tap("drawer.newConversation")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any)["chat.draft"].firstMatch.value as? String,
                       "Keep ordinary unsent text")
        XCTAssertFalse(app.staticTexts["chat.message.0.user"].firstMatch.exists)
    }

    func testUnfinishedReplyNeedsConfirmationFromTopAndDrawer() {
        launch(streaming: true); configure(); disableMemory(); compose("[fixture:stream-cancel]"); tap("chat.send")
        assertLabel(app.staticTexts["chat.partialReply"].firstMatch, "串流測試：第一段")
        tap("chat.cancel")
        assertLabel(app.staticTexts["chat.partialStatus"].firstMatch, "已取消・部分回覆未保存")

        tap("chat.newConversation")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.label.contains("開啟新對話前確認"))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未完成的回覆片段尚未保存")).firstMatch.exists)
        ready(alert.buttons["返回目前對話"].firstMatch); alert.buttons["返回目前對話"].tap()
        assertLabel(app.staticTexts["chat.partialReply"].firstMatch, "串流測試：第一段")

        tap("chat.menu"); tap("drawer.newConversation")
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        ready(alert.buttons["返回目前對話"].firstMatch); alert.buttons["返回目前對話"].firstMatch.tap()
        tap("drawer.close")
        tap("chat.newConversation")
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.label.contains("開啟新對話前確認"))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未完成的回覆片段尚未保存")).firstMatch.exists)
        let discard = alert.buttons["捨棄並開啟新對話"].firstMatch
        ready(discard); discard.tap()
        XCTAssertFalse(app.staticTexts["chat.partialReply"].firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any)["chat.draft"].firstMatch.value as? String,
                       "[fixture:stream-cancel]")
        tap("chat.menu")
        XCTAssertTrue(app.staticTexts["drawer.recent.empty"].firstMatch.waitForExistence(timeout: 10))
    }

    func testChangedModelDisablesContinuationFromTheDrawer() {
        launch(); configure(); send("Archive original")
        navigate("settings")
        openModelSettings(in: app)
        // Another main model of the same provider, typed in the main-model picker.
        chooseTypedMainModel("different", provider: "model.invalid", in: app)
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app)
        navigate("chat"); tap("chat.menu")
        let original = revealRecentRow("Archive original")
        XCTAssertFalse(original.isEnabled, "A chat saved with another main model cannot continue on this one.")
        XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
    }

    func testDeletionRemainsAbsentAfterRelaunch() {
        launch(); configure(); send("Archive delete")
        compose("Keep text while deleting saved row")
        // Play's drawer: long-press a chat, then 刪除 and confirm.
        tap("chat.menu")
        let saved = revealRecentRow("Archive delete")
        let uuid = String(saved.identifier.dropFirst("drawer.recent.row.".count))
        ready(saved); saved.press(forDuration: 1)
        let delete = app.buttons["drawer.recent.delete." + uuid].firstMatch
        ready(delete); delete.tap()
        let confirm = app.buttons["drawer.recent.delete.confirm"].firstMatch
        ready(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["drawer.recent.empty"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(recentRow("Archive delete").exists)
        tap("drawer.close")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "Keep text while deleting saved row")
        launch(reset: false); tap("chat.menu")
        XCTAssertTrue(app.staticTexts["drawer.recent.empty"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(recentRow("Archive delete").exists)
    }

    func testCancelledRunAndUnsentDraftAreNotClaimedAsSaved() {
        launch(); configure()
        compose("[fixture:wait]"); tap("chat.send")
        ready(app.buttons["chat.cancel"].firstMatch)
        assertArchiveUnavailableDuringRun()
        tap("chat.cancel")
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "[fixture:wait]")
        XCTAssertFalse(app.staticTexts["chat.message.0.user"].firstMatch.exists)
        tap("chat.menu")
        XCTAssertTrue(app.staticTexts["drawer.recent.empty"].firstMatch.waitForExistence(timeout: 10))
        launch(reset: false)
        XCTAssertFalse(app.staticTexts["chat.message.0.user"].firstMatch.exists)
        XCTAssertNotEqual(chatDraftControl(in: app).value as? String, "[fixture:wait]")
        tap("chat.menu")
        XCTAssertTrue(app.staticTexts["drawer.recent.empty"].firstMatch.waitForExistence(timeout: 10))
    }

    /// Android MessageMenu: quote a reply and send with it, then ask again from your
    /// own message; its words replace a typed draft, a waiting quote goes, and
    /// they wait unsent in the branch and can be sent there.
    func testMessageMenuQuotesAndAsksAgainLikeAndroid() {
        launch(); configure(); send("Menu first")
        openMessageMenu("chat.message.1.assistant")
        for id in ["copy", "quote", "selectText", "report", "branch"] {
            XCTAssertTrue(app.buttons["chat.messageMenu." + id].firstMatch.exists, id)
        }
        XCTAssertFalse(app.buttons["chat.messageMenu.askAgain"].firstMatch.exists, "a reply is not asked again")
        tap("chat.messageMenu.quote")
        assertLabel(app.staticTexts["chat.quote.text"].firstMatch, "引用渥屋助理：測試回覆：Menu first")
        compose("Explain"); tap("chat.send")
        XCTAssertTrue(app.staticTexts["chat.message.3.assistant"].firstMatch.waitForExistence(timeout: 15))
        assertLabel(app.staticTexts["chat.message.2.user"].firstMatch, "Explain")
        assertLabel(app.descendants(matching: .any)["chat.message.2.quote"].firstMatch, "引用渥屋助理：測試回覆：Menu first")
        XCTAssertFalse(app.staticTexts["chat.quote.text"].firstMatch.exists, "the quote went with the message")

        // Like Android (onBranchRetry), nothing asks first: the typed draft is
        // replaced and the waiting quote cleared.
        compose("Draft to replace")
        openMessageMenu("chat.message.3.assistant"); tap("chat.messageMenu.quote")
        let waitingQuote = app.staticTexts["chat.quote.text"].firstMatch
        XCTAssertTrue(waitingQuote.waitForExistence(timeout: 5))
        openMessageMenu("chat.message.2.user")
        XCTAssertTrue(app.buttons["chat.messageMenu.askAgain"].firstMatch.exists)
        XCTAssertFalse(app.buttons["chat.messageMenu.branch"].firstMatch.exists, "your own message is not a branch point")
        XCTAssertFalse(app.buttons["chat.messageMenu.report"].firstMatch.exists, "only AI replies are reported")
        tap("chat.messageMenu.askAgain")
        assertLabel(app.staticTexts["chat.toast"].firstMatch, "已建立分支")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "Explain")
        assertGone(waitingQuote)
        assertLabel(app.staticTexts["chat.message.0.user"].firstMatch, "Menu first")
        XCTAssertFalse(app.staticTexts["chat.message.2.user"].firstMatch.exists, "the branch ends before that message")
        tap("chat.send")
        assertLabel(app.staticTexts["chat.message.3.assistant"].firstMatch, "測試回覆：Explain")
        assertBranchInSidebar("Menu first · 分支")
    }

    /// Like Android (onBranch), 從這裡分支 opens the branch with an empty input
    /// bar: a typed draft and a waiting quote are cleared without asking. Copy
    /// and 選取文字 use plain text.
    func testMessageMenuBranchesCopiesAndSelectsTextLikeAndroid() {
        launch(); configure(); send("Menu first")
        compose("Unsent words")
        openMessageMenu("chat.message.1.assistant"); tap("chat.messageMenu.quote")
        let quote = app.staticTexts["chat.quote.text"].firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5))
        openMessageMenu("chat.message.1.assistant"); tap("chat.messageMenu.branch")
        assertLabel(app.staticTexts["chat.toast"].firstMatch, "已建立分支")
        assertGone(quote)
        let draft = chatDraftControl(in: app).value as? String ?? ""
        XCTAssertTrue(["", "繼續說點什麼…"].contains(draft), "the branch opens with an empty input bar")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：Menu first")

        openMessageMenu("chat.message.1.assistant"); tap("chat.messageMenu.copy")
        assertLabel(app.staticTexts["chat.toast"].firstMatch, "已複製")
        openMessageMenu("chat.message.0.user"); tap("chat.messageMenu.selectText")
        let body = app.textViews["chat.selectText.body"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "Menu first")
        tap("chat.selectText.done")
        assertGone(body)
        assertBranchInSidebar("Menu first · 分支")
    }

    /// Play's 檢舉 AI 回覆 (964d7bec): the sheet sends the reply's report (to the
    /// UI test relay, never the real one), shows it received, and deletes it.
    func testMessageMenuReportsAReplyLikePlay() {
        launch(); configure(); send("Report me")
        openMessageMenu("chat.message.1.assistant"); tap("chat.messageMenu.report")
        assertLabel(app.staticTexts["chat.report.notice"].firstMatch, "檢舉內容會傳送給開發者。伺服器確認收到前，會保留在這台裝置上等待傳送。")
        XCTAssertTrue(app.staticTexts["chat.report.reference"].firstMatch.label.hasPrefix("回覆編號："))
        assertLabel(app.staticTexts["chat.report.response"].firstMatch, "測試回覆：Report me")
        XCTAssertTrue(app.buttons["chat.report.reason.offensive"].firstMatch.isSelected, "冒犯性內容 is chosen first, as on Play")
        tap("chat.report.reason.unsafe")
        XCTAssertTrue(app.buttons["chat.report.reason.unsafe"].firstMatch.isSelected)
        XCTAssertFalse(app.buttons["chat.report.reason.offensive"].firstMatch.isSelected)
        assertLabel(app.buttons["chat.report.confirm"].firstMatch, "送出檢舉")
        tap("chat.report.confirm")
        let status = app.staticTexts["chat.report.status"].firstMatch
        let received = NSPredicate(format: "exists == true AND label BEGINSWITH %@", "開發者已收到。編號：")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: received, object: status)], timeout: 15), .completed)
        assertLabel(app.buttons["chat.report.dismiss"].firstMatch, "關閉")
        tap("chat.report.delete")
        let confirm = app.alerts.buttons["刪除檢舉"].firstMatch
        ready(confirm); confirm.tap()
        assertLabel(app.staticTexts["chat.report.deleted"].firstMatch, "檢舉已刪除。")
        assertGone(status)
        tap("chat.report.dismiss")
        assertGone(app.staticTexts["chat.report.notice"].firstMatch)
        openMessageMenu("chat.message.0.user")
        XCTAssertFalse(app.buttons["chat.messageMenu.report"].firstMatch.exists, "only AI replies are reported")
        tap("chat.messageMenu.copy")
    }

    private func openMessageMenu(_ identifier: String) {
        // Wait out the last toast, as a person would, before the next long press.
        assertGone(app.staticTexts["chat.toast"].firstMatch)
        let message = app.staticTexts[identifier].firstMatch
        ready(message); message.press(forDuration: 1)
        XCTAssertTrue(app.buttons["chat.messageMenu.copy"].firstMatch.waitForExistence(timeout: 5))
    }
    private func assertGone(_ element: XCUIElement) {
        let gone = NSPredicate(format: "exists == false")
        if !gone.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: 5), .completed)
        }
    }
    /// Android's sidebar marks a branch (從另一個對話分支); its title gets " · 分支".
    private func assertBranchInSidebar(_ title: String) {
        tap("chat.menu")
        let row = revealRecentRow(title)
        XCTAssertTrue((row.value as? String ?? "").contains("從另一個對話分支"))
    }
    private func launch(reset: Bool = true, streaming: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", namespace]
        if streaming { app.launchArguments.append("-UITestChatStreaming") }
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
        tap("settings.dismissKeyboard")
        write("fixture", field: app.textFields["settings.model"].firstMatch, scroll: true)
        tap("settings.dismissKeyboard")
        let key = app.secureTextFields["settings.apiKey"].firstMatch
        revealLearningElement(key, in: app); ready(key); key.tap(); prepareKeyboard(); key.typeText("fixture-key")
        tap("settings.dismissKeyboard"); tap("setup.test", scroll: true)
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app)
        navigate("chat"); assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }
    private func disableMemory() {
        navigate("memory")
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app); ready(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        let native = toggle.switches.firstMatch
        let target = native.exists ? native : toggle
        ready(target)
        XCTAssertTrue(target.isHittable)
        target.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: toggle)], timeout: 10), .completed)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        navigate("chat")
    }
    private func compose(_ text: String) {
        let draft = chatDraftControl(in: app)
        write(text, field: draft, scroll: false); tap("chat.dismissKeyboard")
        XCTAssertEqual(draft.value as? String, text)
    }
    private func send(_ text: String) {
        compose(text); tap("chat.send")
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "測試回覆：" + text)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
    }
    private func recentRow(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "drawer.recent.row.", title)).firstMatch
    }
    @discardableResult private func assertRecentRowValue(_ title: String, identifier: String,
                                                          value: String) -> XCUIElement {
        let visible = revealRecentRow(title)
        XCTAssertEqual(visible.identifier, identifier, "The saved conversation must keep its UUID")
        let matching = app.buttons.matching(identifier: identifier)
        let current = matching.firstMatch
        let status = NSPredicate(format: "exists == true AND value == %@", value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: status, object: current)],
                                  timeout: 5), .completed, "The same visible row must update before relaunch")
        XCTAssertEqual(matching.count, 1, "No stale duplicate accessibility row may mask the current row")
        XCTAssertEqual(current.label, title)
        XCTAssertEqual(current.value as? String, value)
        return current
    }
    private func revealRecentRow(_ title: String) -> XCUIElement {
        let scroll = app.scrollViews["drawer.scroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let target = recentRow(title)
        for _ in 0..<4 where !target.exists || !scroll.frame.contains(target.frame) {
            scroll.swipeUp()
        }
        XCTAssertTrue(target.exists)
        XCTAssertTrue(scroll.frame.contains(target.frame))
        return target
    }
    private func navigate(_ section: String) {
        navigateMikaSection(section, in: app)
        XCTAssertTrue(app.staticTexts[section + ".status"].firstMatch.waitForExistence(timeout: 5))
    }
    private func write(_ text: String, field: XCUIElement, scroll: Bool) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field)
        if !scroll {
            XCTAssertTrue(app.frame.contains(field.frame)); XCTAssertFalse(field.frame.isEmpty)
            XCTAssertLessThanOrEqual(field.frame.maxY, mikaUnobscuredBottom(in: app))
        }
        field.tap(); prepareKeyboard()
        var entered = "", remaining = text[...]
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(entered.isEmpty ? 1 : 16))
            field.typeText(chunk); entered += chunk; remaining = remaining.dropFirst(chunk.count)
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
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
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
    private func assertArchiveUnavailableDuringRun() {
        tap("chat.menu")
        let newConversation = app.buttons["drawer.newConversation"].firstMatch
        XCTAssertTrue(newConversation.waitForExistence(timeout: 5))
        XCTAssertFalse(newConversation.isEnabled, "A new chat waits until the run ends")
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
