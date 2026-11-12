import Foundation

@MainActor
final class ChatFakeDriver: VoiceInputDriver {
    var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var current: UUID!
    var cancelled: [UUID] = []
    var finished: [UUID] = []
    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) { current = id; callbacks[id] = emit }
    func finish(id: UUID) { finished.append(id) }
    func cancel(id: UUID) { cancelled.append(id) }
    func emit(_ event: VoiceInputEvent, _ id: UUID) { callbacks[id]?(id, event) }
}

/// Retains real callbacks through cancellation so a test can deliver a
/// delayed synthetic permission response without relying on sleep or timing.
@MainActor
final class DelayedPermissionVoiceDriver: VoiceInputDriver {
    private var permits: [UUID: () -> Bool] = [:]
    private var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var current: UUID?
    var cancellations: [UUID] = []
    var microphoneRequests: [UUID] = []
    var engineStarts: [UUID] = []
    var activations: [UUID] = []
    var onActivation: (() -> Void)?
    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        current = id; permits[id] = mayContinue; callbacks[id] = emit
    }
    func finish(id: UUID) {}
    func cancel(id: UUID) { cancellations.append(id) }
    private func allowed(_ id: UUID) -> Bool {
        guard permits[id]?() == true else { callbacks[id]?(id, .cancelled); return false }
        return true
    }
    func completeSpeechPermission(_ id: UUID) {
        guard allowed(id) else { return }
        microphoneRequests.append(id)
    }
    func completeMicrophonePermission(_ id: UUID) {
        guard allowed(id) else { return }
        activations.append(id)
        onActivation?()
        guard allowed(id) else { return }
        engineStarts.append(id)
    }
    func emitFinal(_ id: UUID, _ text: String) { callbacks[id]?(id, .final(text)) }
}

@main struct ChatVoiceChecks {
    @MainActor static func main() async {
        var time = 10.0
        var conversation = "one"
        var draft = "原文"
        var writes = 0
        let driver = ChatFakeDriver()
        let controller = ChatVoiceController(driver: driver, now: { time }, conversation: { conversation },
            readDraft: { draft }, writeDraft: { draft = $0; writes += 1 })
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { fatalError(message) }
        }
        controller.begin(gestureStartedAt: time - 0.3)
        let first = driver.current!
        driver.emit(.partial("語"), first)
        time += 0.3
        controller.release()
        check(driver.finished == [first], "release finishes recognition")
        draft = "編輯後"
        driver.emit(.final("語音"), first)
        check(draft == "編輯後語音" && writes == 1, "merge into current draft once")
        driver.emit(.final("重複"), first)
        check(writes == 1, "duplicate result ignored")

        controller.begin(gestureStartedAt: time - 1)
        let cancelled = driver.current!
        controller.drag(upwardDistance: 71)
        driver.emit(.final("不應加入"), cancelled)
        controller.release()
        driver.emit(.final("過期"), cancelled)
        check(writes == 1 && driver.cancelled.contains(cancelled), "slide cancellation discards early and late finals")

        controller.begin(gestureStartedAt: time - 1)
        let switching = driver.current!
        controller.release()
        conversation = "two"
        driver.emit(.final("舊對話"), switching)
        check(writes == 1, "identity fence works before UI change observer")
        controller.cancel()
        controller.begin(gestureStartedAt: time - 1)
        let background = driver.current!
        controller.cancel()
        driver.emit(.final("背景"), background)
        check(writes == 1 && driver.cancelled.contains(background), "lifecycle cancel invalidates result")

        controller.begin(gestureStartedAt: time - 1)
        let next = driver.current!
        driver.emit(.final("過去背景"), background)
        controller.drag(upwardDistance: 71)
        controller.drag(upwardDistance: 20)
        controller.release()
        driver.emit(.final(" hello"), next)
        check(draft == "編輯後語音 hello" && writes == 2, "new session survives stale callback and disarmed cancellation")

        controller.begin(gestureStartedAt: time - 0.1)
        let short = driver.current!
        controller.release()
        check(controller.state == .noMatch && driver.cancelled.contains(short), "short gesture cancels")
        controller.begin(gestureStartedAt: time - 1)
        let denied = driver.current!
        driver.emit(.failed(.microphoneDenied), denied)
        check(controller.state == .failed(.microphoneDenied), "permission error exposed")
        controller.begin(gestureStartedAt: time - 1)
        let timeout = driver.current!
        controller.release()
        time += 6
        controller.tick()
        driver.emit(.final("太晚"), timeout)
        check(controller.state == .failed(.timeout) && writes == 2, "deadline discards late result")
        controller.begin(gestureStartedAt: time)
        let held = driver.current!
        driver.emit(.final("未放開"), held)
        time += 60
        controller.tick()
        controller.release()
        check(controller.state == .failed(.timeout) && writes == 2 && driver.cancelled.contains(held),
              "held deadline never commits even an early final")
        // Actual preference store -> actual composer controller, without a
        // microphone. Separate UserDefaults instances model another window.
        let suite = "woow-voice-choice-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VoiceChoiceStore(defaults: defaults)
        let secondStore = VoiceChoiceStore(defaults: UserDefaults(suiteName: suite)!)
        let preferences = VoicePreferences(store: store)
        check(preferences.choice == .automatic && preferences.authorization != nil, "unset preference preserves existing on-device behavior")
        let gatedDriver = ChatFakeDriver()
        var gatedDraft = "draft", gatedWrites = 0
        let gated = ChatVoiceController(driver: gatedDriver, now: { time }, conversation: { conversation },
            readDraft: { gatedDraft }, writeDraft: { gatedDraft = $0; gatedWrites += 1 },
            voiceAuthorization: { preferences.authorization })
        preferences.select(.off)
        check(secondStore.load() == .off, "off persisted for another window")
        gated.begin(gestureStartedAt: time - 1)
        check(gatedDriver.current == nil && gated.state == .idle, "off never starts microphone driver")
        preferences.select(.system)
        check(secondStore.load() == .system, "system choice persisted")
        gated.onStateChange = { state in
            if case .listening = state { secondStore.select(.off) }
        }
        gated.begin(gestureStartedAt: time - 1)
        check(gatedDriver.current == nil && gated.state == .idle, "reentrant settings change prevents driver start")
        gated.onStateChange = nil
        preferences.select(.system)
        gated.begin(gestureStartedAt: time - 1)
        let revoked = gatedDriver.current!
        gated.release()
        secondStore.select(.off)
        secondStore.select(.system)
        gatedDriver.emit(.final("stale"), revoked)
        check(gatedWrites == 0 && gatedDraft == "draft", "off/on ABA revokes an old result")
        gated.begin(gestureStartedAt: time - 1)
        let running = gatedDriver.current!
        secondStore.select(.off)
        gated.tick()
        gatedDriver.emit(.final("late"), running)
        check(gatedDriver.cancelled.contains(running) && gatedWrites == 0, "off cancels capture and blocks late result")
        secondStore.select(.system)
        gated.begin(gestureStartedAt: time - 1)
        let resumed = gatedDriver.current!
        gated.release()
        gatedDriver.emit(.final("works"), resumed)
        check(gatedDraft == "draft works" && gatedWrites == 1, "system selection retains on-device composer")
        gated.begin(gestureStartedAt: time - 1)
        let early = gatedDriver.current!
        gatedDriver.emit(.final("early"), early)
        secondStore.select(.off)
        secondStore.select(.system)
        gated.release()
        check(gatedDriver.cancelled.contains(early) && gatedWrites == 1, "off/on revokes an early result before release")
        defaults.set("future-provider", forKey: VoiceChoiceStore.key)
        check(store.load() == .unavailable && store.snapshot().authorization == nil, "unknown choice fails closed")
        gated.begin(gestureStartedAt: time - 1)
        check(gatedDriver.current == early, "unknown choice never starts device recognition")
        let uuid = UUID().uuidString
        check(VoiceChoiceStore.suiteName(arguments: ["-UITestMode", "-UITestNamespace", uuid], debug: true)
              == VoiceChoiceStore.productionSuite + ".test." + uuid, "UI test namespace isolated")
        check(VoiceChoiceStore.suiteName(arguments: ["-UITestMode"], debug: true) == nil, "invalid test namespace fails closed")
        check(VoiceChoiceStore.suiteName(arguments: ["-UITestMode", "-UITestNamespace", uuid], debug: false)
              == VoiceChoiceStore.productionSuite, "release ignores test arguments")
        #if DEBUG
        let fixtureArgs = ["-UITestMode", "-UITestNamespace", uuid]
        let fixture = VoiceChoiceStore.application(arguments: fixtureArgs)
        fixture.select(.off)
        check(VoiceChoiceStore.application(arguments: fixtureArgs).load() == .off, "fixture selection survives relaunch")
        check(VoiceChoiceStore.application(arguments: fixtureArgs + ["-UITestResetStorage"]).load() == .automatic,
              "fixture reset clears only its namespace")
        #endif
        // Production state machine + the real preference binding; the fake
        // driver deliberately retains pending permission callbacks after cancel.
        let delayedStore = VoiceChoiceStore(defaults: defaults)
        delayedStore.select(.system)
        let delayedPreferences = VoicePreferences(store: delayedStore)
        let delayed = DelayedPermissionVoiceDriver()
        var result = ""
        let guarded = ChatVoiceController(driver: delayed, now: { time }, conversation: { conversation },
            readDraft: { result }, writeDraft: { result = $0 },
            voiceAuthorization: { delayedPreferences.authorization })
        let binding = ChatVoicePreferenceBinding(preferences: delayedPreferences, controller: guarded)
        _ = binding
        guarded.begin(gestureStartedAt: time - 1)
        let beforeNotification = delayed.current!
        secondStore.select(.off)
        delayed.completeSpeechPermission(beforeNotification)
        delayed.completeMicrophonePermission(beforeNotification)
        check(delayed.microphoneRequests.isEmpty && delayed.engineStarts.isEmpty,
              "live settings guard blocks permission callbacks before notification or tick")
        check(delayed.cancellations.contains(beforeNotification) && guarded.state == .idle,
              "rejected permission callback immediately cancels state")
        delayedPreferences.select(.system)
        guarded.begin(gestureStartedAt: time - 1)
        let notificationSession = delayed.current!
        secondStore.select(.off)
        // Deliver notification while the permissions are still pending, with
        // no permission callback and no controller tick.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        for _ in 0..<100 where !delayed.cancellations.contains(notificationSession) { await Task.yield() }
        check(delayed.cancellations.contains(notificationSession) && guarded.state == .idle,
              "settings notification actively cancels without waiting for tick")
        delayedPreferences.select(.system)
        guarded.begin(gestureStartedAt: time - 1)
        let betweenPermissions = delayed.current!
        delayed.completeSpeechPermission(betweenPermissions)
        check(delayed.microphoneRequests == [betweenPermissions], "normal speech permission reaches microphone request")
        delayedPreferences.select(.off)
        check(delayed.cancellations.contains(betweenPermissions), "same-process settings action cancels synchronously")
        delayed.completeMicrophonePermission(betweenPermissions)
        check(delayed.engineStarts.isEmpty, "late microphone permission cannot start audio engine")
        delayedPreferences.select(.system)
        guarded.begin(gestureStartedAt: time - 1)
        let activationRace = delayed.current!
        delayed.completeSpeechPermission(activationRace)
        delayed.onActivation = { secondStore.select(.off) }
        delayed.completeMicrophonePermission(activationRace)
        delayed.onActivation = nil
        check(delayed.activations.contains(activationRace) && delayed.engineStarts.isEmpty,
              "settings change during audio activation blocks engine start")
        delayedPreferences.refresh()
        check(delayed.cancellations.contains(activationRace), "activation race is cancelled")
        delayedPreferences.select(.system)
        guarded.begin(gestureStartedAt: time - 1)
        let abaPermission = delayed.current!
        delayed.completeSpeechPermission(abaPermission)
        secondStore.select(.off); secondStore.select(.system)
        delayed.completeMicrophonePermission(abaPermission)
        check(delayed.engineStarts.isEmpty, "off/on ABA cannot authorize an old permission callback")
        delayedPreferences.refresh()
        check(delayed.cancellations.contains(abaPermission), "same-label revision change cancels active capture")
        guarded.begin(gestureStartedAt: time - 1)
        let backgroundPermission = delayed.current!
        delayed.completeSpeechPermission(backgroundPermission)
        guarded.cancel() // The production scene/background and explicit cancel path.
        delayed.completeMicrophonePermission(backgroundPermission)
        check(delayed.engineStarts.isEmpty && delayed.cancellations.contains(backgroundPermission),
              "background cancellation fences delayed permission")
        guarded.begin(gestureStartedAt: time - 1)
        let userCancelledPermission = delayed.current!
        delayed.completeSpeechPermission(userCancelledPermission)
        guarded.cancel()
        delayed.completeMicrophonePermission(userCancelledPermission)
        check(delayed.engineStarts.isEmpty && delayed.cancellations.contains(userCancelledPermission),
              "explicit cancellation fences delayed permission")
        guarded.begin(gestureStartedAt: time - 1)
        let validPermission = delayed.current!
        delayed.completeSpeechPermission(validPermission)
        delayed.completeMicrophonePermission(backgroundPermission)
        delayed.completeMicrophonePermission(validPermission)
        check(delayed.engineStarts == [validPermission], "old callback cannot affect the new valid session")
        guarded.release()
        delayed.emitFinal(validPermission, "ok")
        check(result == "ok", "unchanged permission and normal release still work")
        delayed.emitFinal(backgroundPermission, "late")
        check(result == "ok", "late cancelled result cannot overwrite draft")
        print("PASS ChatVoice composer semantics (fake driver; no Apple SDK)")
    }
}
