import Foundation

@main struct VoiceUITestFixtureChecks {
    @MainActor static func main() {
        let id = UUID().uuidString
        let valid = ["app", "-UITestMode", "-UITestNamespace", id, "-UITestResetStorage", "-UITestVoiceFixture"]
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError(message) }
        }
        check(VoiceUITestFixture.valid(arguments: valid, simulator: true), "isolated simulator enabled")
        check(!VoiceUITestFixture.valid(arguments: valid, simulator: false), "physical device denied")
        check(!VoiceUITestFixture.valid(arguments: valid + ["-LiveModelUITest"], simulator: true), "live mode denied")
        check(!VoiceUITestFixture.valid(arguments: valid + ["-UITestVoiceFixture"], simulator: true), "duplicate denied")
        check(!VoiceUITestFixture.valid(arguments: valid + ["-UITestChatStreaming"], simulator: true), "unrelated fixture denied")
        check(!VoiceUITestFixture.valid(arguments: ["app", "-UITestMode", "-UITestNamespace", "bad", "-UITestVoiceFixture"], simulator: true), "invalid namespace denied")
        check(VoiceUITestFixture.selected(arguments: ["app"]) == nil, "explicit opt-in required")
        check(VoiceUITestFixture.selected(arguments: valid) === VoiceUITestFixture.shared, "explicit opt-in selects fake driver")
        let fixture = VoiceUITestFixture()
        let session = UUID()
        var received: [VoiceInputEvent] = []
        fixture.start(id: session) { id, event in
            check(id == session, "result session identity")
            received.append(event)
        }
        fixture.finish(id: session)
        fixture.cancel(id: session)
        fixture.emitLatest()
        check(received == [.final("fixture voice")], "cancelled callback actually delivered")
        check(fixture.observation == "start=1 finish=1 cancel=1 emit=1", "all events observable")
        let integrated = VoiceUITestFixture()
        var draft = "Existing"
        var now = 10.0
        let controller = ChatVoiceController(driver: integrated, now: { now }, conversation: { "one" },
                                             readDraft: { draft }, writeDraft: { draft = $0 })
        controller.begin(gestureStartedAt: now - 1)
        controller.release()
        check(draft == "Existing", "no result before explicit emission")
        integrated.emitLatest()
        check(draft == "Existing fixture voice", "fixture result enters current draft")
        now += 1
        controller.begin(gestureStartedAt: now - 1)
        controller.cancel()
        integrated.emitLatest()
        check(draft == "Existing fixture voice", "deliberate stale fixture callback is rejected")
        print("PASS voice UI fixture gates and deliberately late callback")
    }
}
