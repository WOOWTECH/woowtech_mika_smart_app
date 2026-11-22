import Foundation
import XCTest

/// Controlled native regressions, not commercial/provider acceptance. Existing DEBUG
/// fixtures supply synthetic text/errors in a UUID namespace; ChatSession, archive,
/// branching, keyboard, gestures and rendering remain the production paths.
final class ChatReturnToLatestUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private var observations: [[String: Any]] = []
    private var timings: [[String: Any]] = []
    private var activePhase: String?
    private var phaseStarted: TimeInterval?

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        let failures = testRun?.failureCount ?? 0
        var report: [String: Any] = [
            "synthetic": true, "namespace": namespace, "maximumSeconds": 300,
            "phases": timings, "frames": observations,
            "failuresObservedBeforeTeardown": failures, "finalResultSource": "xcresult",
            "timingScope": "native actions and AX observations, including automation overhead"
        ]
        if let activePhase, let phaseStarted {
            report["unfinishedPhase"] = activePhase
            report["unfinishedPhaseSeconds"] = ProcessInfo.processInfo.systemUptime - phaseStarted
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "return-control-observations.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        if failures > 0, app.state == .runningForeground {
            capture("return-control-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "return-control-failure-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testTerminalErrorRemainsReadableWithReturnControlAndCompactKeyboard() {
        phase("seed_short_history_and_terminal_error") {
            launch()
            // Forty-eight short lines overflow even a tall iPad transcript, with
            // only two real sends. No archive injection or slow stream is needed.
            let text = (1...48).map { String(format: "Line %02d", $0) }.joined(separator: "\n")
            send(text)
            expectLabel(message(1, role: "assistant"), "測試回覆：" + text)
            send("[fixture:error-once]")
            // The fixture throws raw URLError, which uses the production generic failure copy.
            expectLabel(terminalError, "沒有完成\n傳送失敗。請檢查模型設定或網路後重試。")
            expect(NSPredicate(format: "exists == false"), on: app.buttons["chat.cancel"].firstMatch)
            XCTAssertFalse(app.staticTexts["chat.error"].exists, "The error must be a terminal transcript turn")
            XCTAssertFalse(app.staticTexts["chat.archiveNotice"].exists)
            XCTAssertEqual(messageNodes.count, 4)
            XCTAssertFalse(app.buttons["chat.history.latest"].exists)
        }

        // iPhone supports portrait only. Four unsent lines reduce the real viewport
        // through the production multiline composer without changing device orientation.
        let compactDraft = "Unsent line 1\nUnsent line 2\nUnsent line 3\nUnsent line 4"
        var portraitViewportHeight: CGFloat = 0
        var portraitDraftHeight: CGFloat = 0
        func assertCompactDraftIsUnsent() {
            XCTAssertEqual(chatDraftControl(in: app).value as? String, compactDraft)
            XCTAssertEqual(messageNodes.count, 4)
            XCTAssertFalse(message(4, role: "user").exists, "Compact-layout text must remain an unsent draft")
            XCTAssertFalse(app.buttons["chat.cancel"].firstMatch.exists)
        }
        for compact in [false, true] {
            let mode = compact ? "portrait_compact_draft" : "portrait"
            phase(mode + "_keyboard_on") {
                focusDraft()
                XCTAssertGreaterThan(app.frame.height, app.frame.width)
                if compact {
                    let draft = chatDraftControl(in: app)
                    draft.typeText(compactDraft)
                    assertCompactDraftIsUnsent()
                    expect(NSPredicate { _, _ in
                        draft.frame.height > portraitDraftHeight
                            && self.transcript.frame.height < portraitViewportHeight
                    }, on: transcript)
                }
                // No corrective Return/Done tap before this observation.
                assertErrorLayout(mode + "-keyboard-on", fullError: true, requiresReturn: false)
                if !compact {
                    portraitViewportHeight = transcript.frame.height
                    portraitDraftHeight = chatDraftControl(in: app).frame.height
                }
            }
            phase(mode + "_read_earlier") {
                let before = terminalError.frame.minY
                let viewport = transcript.frame
                XCTAssertGreaterThan(viewport.height, terminalError.frame.height)
                let origin = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                origin.press(forDuration: 0.05,
                             thenDragTo: origin.withOffset(CGVector(dx: 0, dy: 24)),
                             withVelocity: .slow, thenHoldForDuration: 0.2)
                ready(returnButton)
                expect(NSPredicate { _, _ in
                    let current = self.terminalError
                    let exists = current.exists
                    let frame = exists ? current.frame : .zero
                    self.observations.append(["phase": mode + "-drag-observation", "exists": exists,
                        "beforeY": Double(before), "error": self.rect(frame),
                        "viewport": self.rect(self.transcript.frame)])
                    return exists && !frame.isEmpty && frame.minY >= before + 8
                }, on: app)
                // Reading earlier intentionally allows the tail to leave view.
                // Still require real error/control/composer frames and no overlay.
                assertErrorLayout(mode + "-held-keyboard-on", fullError: false, requiresReturn: true)
                if compact { assertCompactDraftIsUnsent() }
            }
            phase(mode + "_keyboard_off_while_held") {
                tap("chat.dismissKeyboard")
                expect(NSPredicate(format: "exists == false"), on: app.keyboards.firstMatch)
                // The enlarged viewport must show the entire short failed turn
                // while follow remains held: this is the overlap regression.
                assertErrorLayout(mode + "-held-keyboard-off", fullError: true, requiresReturn: true)
                if compact { assertCompactDraftIsUnsent() }
            }
            phase(mode + "_explicit_return_then_keyboard") {
                tap("chat.returnToLatest")
                expect(NSPredicate(format: "exists == false"), on: returnButton, seconds: 5)
                assertErrorLayout(mode + "-returned", fullError: true, requiresReturn: false)
                focusDraft()
                assertErrorLayout(mode + "-returned-keyboard-on", fullError: true, requiresReturn: false)
                tap("chat.dismissKeyboard")
                expect(NSPredicate(format: "exists == false"), on: app.keyboards.firstMatch)
                if compact { assertCompactDraftIsUnsent() }
            }
        }
    }

    func testEightyMessageBranchSwitchesToPagedTranscriptOnAcceptedSend() {
        phase("seed_and_open_original_999") {
            launch(longHistory: true)
            // ChatSession loads its archive before the fixture seeds it; cold-load the preserved seed.
            app.terminate()
            launch(reset: false)
            tap("chat.menu")
            tap("drawer.recent.row." + namespace)
            expect(NSPredicate(format: "exists == true AND label CONTAINS %@", "LH-END-999"),
                   on: message(1997, role: "assistant"), seconds: 15)
        }
        phase("branch_first_40_turns_via_real_menu") {
            // Earlier lands at page END: reach reply79 without 40 long swipes.
            tap("chat.history.earliest")
            expectRange(first: 0, last: 79, total: 1998)
            tap("chat.history.newer")
            expectRange(first: 80, last: 159, total: 1998)
            tap("chat.history.earlier")
            expectRange(first: 0, last: 79, total: 1998)
            let reply = message(79, role: "assistant")
            expect(NSPredicate(format: "exists == true AND label CONTAINS %@", "LH-END-40"), on: reply)
            guard let pixelWidth = app.screenshot().image.cgImage?.width else {
                XCTFail("Need screenshot pixel size to check page-end alignment")
                return
            }
            let displayScale = CGFloat(pixelWidth) / app.frame.width
            XCTAssertGreaterThan(displayScale, 0)
            let onePixel = 1 / displayScale
            let aligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                // Captured AX text coordinates have Float32 precision; summed
                // viewport coordinates can differ at a shared edge. Keep a one-physical-pixel bound and
                // record full precision before an assertion can end the test.
                let replyFrame = reply.frame, viewport = self.transcript.frame
                let visible = replyFrame.intersection(viewport)
                let delta = replyFrame.maxY - viewport.maxY
                self.observations.append([
                    "phase": "page-end-40", "reply": self.rect(replyFrame),
                    "viewport": self.rect(viewport), "tailDelta": Double(delta),
                    "displayScale": Double(displayScale), "tolerance": Double(onePixel),
                    "visibleHeight": visible.isNull ? 0 : Double(visible.height)
                ])
                return !visible.isNull && visible.height >= 44 && abs(delta) <= onePixel
            }, object: reply)
            let alignmentResult = XCTWaiter.wait(for: [aligned], timeout: 10)
            print("RETURN_CONTROL_PAGE_END " + String(data: try! JSONSerialization.data(
                withJSONObject: observations, options: [.sortedKeys]), encoding: .utf8)!)
            XCTAssertEqual(alignmentResult, .completed)
            // The long reply's midpoint may be offscreen; press its actual visible text.
            let visible = reply.frame.intersection(transcript.frame)
            transcript.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visible.midX - transcript.frame.minX,
                                     dy: visible.midY - transcript.frame.minY)).press(forDuration: 1)
            tap("chat.messageMenu.branch")
            expect(NSPredicate(format: "exists == false"), on: app.staticTexts["chat.history.range"].firstMatch)
            XCTAssertEqual(messageNodes.count, 80)
            XCTAssertTrue(message(0, role: "user").label.hasPrefix("LH-SYNTHETIC-999 第1輪"))
            XCTAssertTrue(message(79, role: "assistant").label.contains("LH-END-40"))
            XCTAssertFalse(message(80, role: "user").exists)
            XCTAssertFalse(app.buttons["chat.history.latest"].exists)
        }
        phase("accepted_send_observes_81_before_completion") {
            send("[fixture:wait]")
            expectLabel(message(80, role: "user"), "[fixture:wait]")
            ready(app.buttons["chat.cancel"].firstMatch)
            expectRange(first: 2, last: 80, total: 81)
            XCTAssertEqual(messageNodes.count, 79, "79 saved/current entries plus the live tail fit the window")
            XCTAssertFalse(message(0, role: "user").exists)
            XCTAssertFalse(message(81, role: "assistant").exists, "Observe the odd threshold before completing the turn")
            XCTAssertFalse(returnButton.exists)
            ready(app.buttons["chat.history.earliest"].firstMatch)
            capture("return-control-81-in-flight")
            tap("chat.cancel")
            expectLabel(message(81, role: "assistant"), "已停止。")
            expectRange(first: 2, last: 81, total: 82)
            XCTAssertEqual(messageNodes.count, 80)
            XCTAssertFalse(returnButton.exists)
            expect(NSPredicate { _, _ in
                let stopped = self.message(81, role: "assistant")
                let exists = stopped.exists
                let frame = exists ? stopped.frame : .zero
                let viewport = self.transcript.frame
                self.observations.append(["phase": "cancelled-82-observation", "exists": exists,
                    "message": self.rect(frame), "viewport": self.rect(viewport)])
                return exists && !frame.isEmpty && viewport.contains(frame)
            }, on: app)
            XCTAssertFalse(app.staticTexts["chat.archiveNotice"].exists)
        }
        phase("paged_first_latest_and_original_preserved") {
            tap("chat.history.earliest")
            expectRange(first: 0, last: 79, total: 82)
            XCTAssertTrue(message(0, role: "user").label.hasPrefix("LH-SYNTHETIC-999 第1輪"))
            tap("chat.history.latest")
            expectRange(first: 2, last: 81, total: 82)
            expectLabel(message(81, role: "assistant"), "已停止。")
            XCTAssertFalse(returnButton.exists)
            tap("chat.menu")
            tap("drawer.recent.row." + namespace)
            expectRange(first: 1918, last: 1997, total: 1998)
            XCTAssertTrue(message(1997, role: "assistant").label.contains("LH-END-999"))
            XCTAssertFalse(message(1998, role: "user").exists)
            capture("return-control-original-999-preserved")
        }
    }

    private var transcript: XCUIElement { app.scrollViews["chat.transcript"].firstMatch }
    private var returnButton: XCUIElement { app.buttons["chat.returnToLatest"].firstMatch }
    private var terminalError: XCUIElement { message(3, role: "assistant") }
    private var messageNodes: XCUIElementQuery {
        transcript.descendants(matching: .any).matching(
            NSPredicate(format: "identifier MATCHES %@", #"^chat\.message\.[0-9]+\.(user|assistant)$"#))
    }

    private func assertErrorLayout(_ name: String, fullError: Bool, requiresReturn: Bool) {
        let draft = chatDraftControl(in: app)
        let attach = app.buttons["chat.attach.toggle"].firstMatch
        var verified: [String: Any]?
        var verifiedReturn = false
        var verifiedDone: CGRect?
        // native283: separate AX queries consumed the 10s waiter during hit
        // testing and then returned an empty application tree. Bind geometry
        // to ONE public snapshot, as the native browser tests do. Keep the
        // same deadline and every visibility/hit-testing assertion.
        let layout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let snapshot = try? self.app.snapshot() else { return false }
            var pending = [snapshot]
            var nodes: [String: XCUIElementSnapshot] = [:]
            var keyboard: CGRect?
            while let node = pending.popLast() {
                if !node.identifier.isEmpty { nodes[node.identifier] = node }
                if node.elementType == .keyboard, !node.frame.isEmpty {
                    keyboard = keyboard.map { $0.union(node.frame) } ?? node.frame
                }
                pending.append(contentsOf: node.children)
            }
            let ids = ["chat.transcript", "chat.message.3.assistant", "chat.draft", "chat.attach.toggle", "chat.send"]
            guard ids.allSatisfy({ nodes[$0] != nil }) else {
                self.observations.append(["phase": name + "-layout-poll", "presence": ids.map { nodes[$0] != nil }])
                return false
            }
            let viewport = nodes[ids[0]]!.frame, error = nodes[ids[1]]!.frame
            let controls = ids.suffix(3).map { nodes[$0]!.frame }
            let appFrame = snapshot.frame
            let bottom = min(appFrame.maxY, keyboard?.minY ?? appFrame.maxY)
            let hasReturn = nodes["chat.returnToLatest"] != nil
            let button = nodes["chat.returnToLatest"]?.frame ?? .zero
            self.observations.append(["phase": name + "-layout-poll", "viewport": self.rect(viewport),
                "error": self.rect(error), "controls": controls.map { self.rect($0) },
                "app": self.rect(appFrame), "unobscuredBottom": Double(bottom),
                "hasReturn": hasReturn, "return": self.rect(button), "singleSnapshot": true])
            guard !viewport.isEmpty, !error.isEmpty, appFrame.contains(viewport),
                  viewport.height >= error.height,
                  controls.allSatisfy({ !$0.isEmpty && appFrame.contains($0) && $0.maxY <= bottom }),
                  viewport.maxY <= controls.map(\.minY).min()!,
                  !fullError || viewport.contains(error) else { return false }
            if requiresReturn && !hasReturn { return false }
            if hasReturn {
                guard !button.isEmpty, nodes["chat.returnToLatest"]!.isEnabled,
                      appFrame.contains(button), button.minY >= viewport.maxY,
                      button.maxY <= controls.map(\.minY).min()!,
                      button.maxY <= bottom else { return false }
            }
            verifiedReturn = hasReturn
            verifiedDone = nodes["chat.dismissKeyboard"]?.frame
            verified = ["phase": name, "epoch": Date().timeIntervalSince1970,
                "fullErrorRequired": fullError, "returnRequired": requiresReturn,
                "viewport": self.rect(viewport), "error": self.rect(error),
                "errorLabel": nodes[ids[1]]!.label, "draft": self.rect(controls[0]),
                "attach": self.rect(controls[1]), "send": self.rect(controls[2]),
                "keyboardVisible": keyboard != nil, "unobscuredBottom": Double(bottom),
                "singleSnapshot": true]
            if hasReturn { verified?["returnControl"] = self.rect(button) }
            return true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [layout], timeout: 10), .completed)
        guard var row = verified else { return }
        // Keep real hit testing, outside the geometry polling closure. No new
        // wait, retry, coordinate tap, or corrective scrolling is introduced.
        XCTAssertTrue(draft.isHittable)
        XCTAssertTrue(attach.isHittable)
        if verifiedReturn {
            XCTAssertTrue(returnButton.isEnabled)
            XCTAssertTrue(returnButton.isHittable)
        }
        if let done = verifiedDone {
            XCTAssertTrue(app.buttons["chat.dismissKeyboard"].firstMatch.isHittable)
            XCTAssertLessThanOrEqual(Double(done.maxY), row["unobscuredBottom"] as! Double)
            row["done"] = rect(done)
        }
        observations.append(row)
        print("RETURN_CONTROL_FRAME " + String(data: try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), encoding: .utf8)!)
        capture(name)
    }

    private func launch(longHistory: Bool = false, reset: Bool = true) {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-WoowSkipOnboarding",
            "-UITestMode", "-UITestNamespace", namespace, "-UITestTranscriptFixture"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        if longHistory { app.launchArguments += ["-UITestLongHistoryFixture", "-UITestLongHistoryTurns", "999"] }
        else { app.launchArguments.append("-UITestTranscriptDiagnostics") }
        app.launchEnvironment = [:]
        app.launch()
        expectLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
        XCTAssertTrue(app.staticTexts["uitest.banner"].exists)
    }

    private func focusDraft() {
        let draft = chatDraftControl(in: app)
        ready(draft); draft.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let introduction = app.buttons["Continue"].firstMatch
        if introduction.exists { introduction.tap() }
        ready(app.buttons["chat.dismissKeyboard"].firstMatch)
    }

    private func send(_ text: String) {
        focusDraft()
        func latin() -> Bool {
            app.keyboards.firstMatch.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
        }
        if !latin() {
            let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
            ready(globe); globe.press(forDuration: 1)
            let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
            ready(english); english.tap()
            expect(NSPredicate { _, _ in latin() }, on: app.keyboards.firstMatch)
        }
        let draft = chatDraftControl(in: app)
        draft.typeText(text)
        XCTAssertEqual(draft.value as? String, text)
        tap("chat.send")
    }

    private func message(_ index: Int, role: String) -> XCUIElement {
        app.descendants(matching: .any)["chat.message.\(index).\(role)"].firstMatch
    }
    private func expectRange(first: Int, last: Int, total: Int) {
        let label = String(format: "第 %1$lld–%2$lld 則，共 %3$lld 則", locale: Locale(identifier: "zh-Hant"),
                           arguments: [Int64(first + 1), Int64(last + 1), Int64(total)])
        expectLabel(app.staticTexts["chat.history.range"].firstMatch, label)
    }
    private func tap(_ id: String) { let button = app.buttons[id].firstMatch; ready(button); button.tap() }
    private func ready(_ element: XCUIElement) {
        expect(NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), on: element)
    }
    private func expectLabel(_ element: XCUIElement, _ text: String) {
        expect(NSPredicate(format: "exists == true AND label == %@", text), on: element, seconds: 15)
    }
    private func expect(_ predicate: NSPredicate, on element: XCUIElement, seconds: TimeInterval = 10,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                                     timeout: seconds), .completed, file: file, line: line)
    }
    private func rect(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)]
    }
    private func phase(_ name: String, _ body: () -> Void) {
        activePhase = name
        let started = ProcessInfo.processInfo.systemUptime
        phaseStarted = started
        print("RETURN_CONTROL_PHASE_BEGIN name=\(name) epoch=\(Date().timeIntervalSince1970)")
        XCTContext.runActivity(named: name) { _ in body() }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        timings.append(["name": name, "seconds": elapsed, "failureCount": testRun?.failureCount ?? 0])
        print("RETURN_CONTROL_PHASE_END name=\(name) seconds=\(elapsed) epoch=\(Date().timeIntervalSince1970)")
        activePhase = nil; phaseStarted = nil
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
