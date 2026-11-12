import Foundation

@MainActor
final class FakeVoiceDriver: VoiceInputDriver {
    var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var starts: [UUID] = []
    var finishes: [UUID] = []
    var cancellations: [UUID] = []
    var finalOnFinish: String?
    var callbackOnCancel = false
    var onCancel: (() -> Void)?
    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        starts.append(id); callbacks[id] = emit
    }
    func finish(id: UUID) {
        finishes.append(id)
        if let finalOnFinish { callbacks[id]?(id, .final(finalOnFinish)) }
    }
    func cancel(id: UUID) {
        cancellations.append(id)
        if callbackOnCancel { callbacks[id]?(id, .final("stale cancellation")) }
        onCancel?()
    }
    func emit(_ event: VoiceInputEvent, for id: UUID) { callbacks[id]?(id, event) }
}

@MainActor
final class FakeAudioLease: VoiceAudioLease {
    var releaseCount = 0
    var activationCount = 0
    var activationResult = true
    var onActivate: (() -> Void)?
    var onRelease: (() -> Void)?
    func activateForRecording() -> Bool {
        activationCount += 1
        onActivate?()
        return activationResult
    }
    func release() { releaseCount += 1; onRelease?() }
}

@MainActor
final class FakeAudioCoordinator: VoiceAudioCoordinating {
    var callbacks: [VoiceAudioRevocation] = []
    var next: (() -> FakeAudioLease?)?
    var duringAcquire: (() -> Void)?
    func acquire(onRevoked: @escaping VoiceAudioRevocation) -> (any VoiceAudioLease)? {
        callbacks.append(onRevoked)
        duringAcquire?()
        return next?()
    }
}

@main
struct VoiceInputChecks {
    @MainActor static func main() {
        var assertions = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            assertions += 1
            guard value() else { fatalError("FAIL: \(message)") }
        }
        var clock: TimeInterval = 0
        let driver = FakeVoiceDriver()
        let machine = VoiceInputStateMachine(driver: driver, now: { clock })
        var draft = "已寫"
        var finals = 0
        machine.onFinal = { text in draft = VoiceDraftJoin.join(draft, text); finals += 1 }
        func begin() -> UUID {
            machine.begin(gestureStartedAt: clock)
            return driver.starts.last!
        }

        let first = begin()
        driver.emit(.partial("中間"), for: first)
        check(machine.state == .listening(partial: "中間", cancelArmed: false, elapsed: 0), "partial is visible")
        clock += 1
        driver.emit(.final(" 完成 "), for: first)
        check(draft == "已寫" && finals == 0, "early final never commits while held")
        machine.release()
        check(draft == "已寫完成" && finals == 1 && machine.state == .idle, "release appends final without sending")
        driver.emit(.final("duplicate"), for: first)
        check(finals == 1, "duplicate final ignored")

        let cancelled = begin()
        clock += 1
        machine.drag(upwardDistance: 81, cancelThreshold: 80)
        driver.emit(.final("不要"), for: cancelled)
        machine.release()
        check(machine.state == .idle && draft == "已寫完成", "armed cancellation discards early final")
        check(driver.cancellations.contains(cancelled), "cancel reaches driver")
        driver.emit(.final("late"), for: cancelled)
        check(finals == 1, "cancelled callback ignored")

        let restored = begin()
        clock += 1
        machine.drag(upwardDistance: 81, cancelThreshold: 80)
        machine.drag(upwardDistance: 80, cancelThreshold: 80)
        machine.release()
        check(machine.state == .finishing && driver.finishes.last == restored, "return from cancel and release requests final")
        draft = "使用者新草稿"
        driver.emit(.final("再說"), for: restored)
        check(draft == "使用者新草稿再說", "final merges with current draft, not captured draft")

        let short = begin()
        clock += 0.49
        machine.release()
        check(machine.state == .noMatch && driver.cancellations.contains(short), "short gesture cancels without finishing")
        check(!driver.finishes.contains(short), "short gesture never triggers finish")

        let expired = begin()
        clock += 1
        machine.release()
        clock += 5
        machine.tick()
        check(machine.state == .failed(.timeout) && driver.cancellations.contains(expired), "finishing has deadline")
        let afterTimeoutCount = finals
        driver.emit(.final("too late"), for: expired)
        check(finals == afterTimeoutCount, "expired final ignored")

        let lateWithoutTick = begin()
        clock += 1
        machine.release()
        clock += 6
        driver.emit(.final("deadline missed"), for: lateWithoutTick)
        check(machine.state == .failed(.timeout) && finals == afterTimeoutCount,
              "late final expires even if UI timer did not tick")

        let replaced = begin()
        clock += 1
        machine.release()
        let newer = begin()
        check(driver.cancellations.contains(replaced), "new press cancels previous session")
        driver.emit(.final("old session"), for: replaced)
        clock += 1
        driver.finalOnFinish = " new "
        machine.release()
        driver.finalOnFinish = nil
        check(draft == "使用者新草稿再說 new" && driver.finishes.last == newer, "synchronous finish callback succeeds once")

        driver.callbackOnCancel = true
        let interrupted = begin()
        machine.cancel()
        driver.emit(.final("later"), for: interrupted)
        check(machine.state == .idle && !draft.contains("stale"), "invalidate before synchronous cancel callback")
        driver.callbackOnCancel = false

        clock = 100
        let long = begin()
        clock += 60
        machine.tick()
        check(machine.state == .failed(.timeout) && driver.cancellations.contains(long), "maximum duration cancels rather than submitting without release")
        driver.emit(.final("late"), for: long)
        check(machine.state == .failed(.timeout), "maximum duration rejects late result")
        let empty = begin()
        clock += 1
        machine.release()
        driver.emit(.final(""), for: empty)
        check(machine.state == .noMatch, "empty final is no match")

        clock = 200
        let longCancelled = begin()
        machine.drag(upwardDistance: 81, cancelThreshold: 80)
        clock += 60
        machine.tick()
        check(machine.state == .idle && driver.cancellations.contains(longCancelled), "timeout honors cancellation gesture")

        let armedFailure = begin()
        clock += 1
        machine.drag(upwardDistance: 81, cancelThreshold: 80)
        driver.emit(.failed(.audio), for: armedFailure)
        machine.release()
        check(machine.state == .idle, "failure while cancellation armed is discarded")
        let disarmedFailure = begin()
        clock += 1
        machine.drag(upwardDistance: 81, cancelThreshold: 80)
        driver.emit(.failed(.audio), for: disarmedFailure)
        machine.drag(upwardDistance: 0, cancelThreshold: 80)
        machine.release()
        check(machine.state == .failed(.audio), "failure survives if user moves back before release")
        let denied = begin()
        driver.emit(.failed(.speechDenied), for: denied)
        check(machine.state == .failed(.speechDenied), "permission error exposed")
        driver.emit(.final("wrong"), for: denied)
        check(machine.state == .failed(.speechDenied), "failed session is expired")

        let examples: [(String, String, String)] = [
            ("", "你好", "你好"), ("你好", "", "你好"), ("你好", "世界", "你好世界"),
            ("你好，", "世界", "你好，世界"), ("한글", "です", "한글です"),
            ("hello", "world", "hello world"), ("你好", "world", "你好 world"),
            ("hello\n", "世界", "hello\n世界"), ("🙂", "你好", "🙂 你好"),
            ("𠀀", "你好", "𠀀你好")
        ]
        for (left, right, expected) in examples { check(VoiceDraftJoin.join(left, right) == expected, "join \(left) + \(right)") }

        let interruptedFinishing = begin()
        clock += 1
        machine.release()
        machine.cancel()
        driver.emit(.final("background"), for: interruptedFinishing)
        check(machine.state == .idle && !draft.contains("background"), "background cancellation expires finishing session")

        let startsBeforeExpiredGesture = driver.starts.count
        machine.begin(gestureStartedAt: clock - 61)
        check(machine.state == .failed(.timeout) && driver.starts.count == startsBeforeExpiredGesture,
              "already expired gesture never starts the driver")

        let reentrantDriver = FakeVoiceDriver()
        let reentrant = VoiceInputStateMachine(driver: reentrantDriver, now: { clock })
        reentrant.onStateChange = { state in if case .listening = state { reentrant.cancel() } }
        reentrant.begin(gestureStartedAt: clock)
        check(reentrantDriver.starts.isEmpty && reentrant.state == .idle, "UI cancellation before start cannot open driver")
        let finishReentrantDriver = FakeVoiceDriver()
        let finishReentrant = VoiceInputStateMachine(driver: finishReentrantDriver, now: { clock })
        finishReentrant.onStateChange = { state in if state == .finishing { finishReentrant.cancel() } }
        finishReentrant.begin(gestureStartedAt: clock)
        clock += 1
        finishReentrant.release()
        check(finishReentrantDriver.finishes.isEmpty && finishReentrant.state == .idle,
              "UI cancellation during finishing prevents driver finish")
        // Regression: a state observer replaces the session synchronously
        // before the former completion can publish its final text.
        let idleDriver = FakeVoiceDriver()
        let idleMachine = VoiceInputStateMachine(driver: idleDriver, now: { clock })
        var idleFinals: [String] = []
        var restarted = false
        idleMachine.onFinal = { idleFinals.append($0) }
        idleMachine.begin(gestureStartedAt: clock)
        let idleOld = idleDriver.starts.last!
        clock += 1
        idleMachine.release()
        idleMachine.onStateChange = { state in
            if state == .idle && !restarted {
                restarted = true
                idleMachine.begin(gestureStartedAt: clock)
            }
        }
        idleDriver.emit(.final("old"), for: idleOld)
        let idleNew = idleDriver.starts.last!
        check(restarted && idleNew != idleOld && idleFinals.isEmpty, "idle reentry suppresses old final")
        check(idleMachine.state == .listening(partial: "", cancelArmed: false, elapsed: 0),
              "idle reentry preserves new listening state")
        clock += 1
        idleMachine.release()
        idleDriver.emit(.final("new"), for: idleNew)
        check(idleFinals == ["new"], "new session final is delivered exactly once")

        let earlyDriver = FakeVoiceDriver()
        let earlyMachine = VoiceInputStateMachine(driver: earlyDriver, now: { clock })
        var earlyFinals: [String] = []
        var earlyRestarted = false
        earlyMachine.onFinal = { earlyFinals.append($0) }
        earlyMachine.begin(gestureStartedAt: clock)
        let earlyOld = earlyDriver.starts.last!
        clock += 1
        earlyDriver.emit(.final("old early"), for: earlyOld)
        earlyMachine.onStateChange = { state in
            if state == .idle && !earlyRestarted {
                earlyRestarted = true
                earlyMachine.begin(gestureStartedAt: clock)
                earlyMachine.cancel()
            }
        }
        earlyMachine.release()
        check(earlyRestarted && earlyFinals.isEmpty && earlyMachine.state == .idle,
              "early final suppressed even if idle observer starts and cancels a session")

        let cancelIdleDriver = FakeVoiceDriver()
        let cancelIdleMachine = VoiceInputStateMachine(driver: cancelIdleDriver, now: { clock })
        var cancelIdleFinals: [String] = []
        cancelIdleMachine.onFinal = { cancelIdleFinals.append($0) }
        cancelIdleMachine.begin(gestureStartedAt: clock)
        let cancelIdleOld = cancelIdleDriver.starts.last!
        clock += 1
        cancelIdleMachine.release()
        cancelIdleMachine.onStateChange = { state in
            if state == .idle { cancelIdleMachine.cancel() }
        }
        cancelIdleDriver.emit(.final("old"), for: cancelIdleOld)
        check(cancelIdleFinals.isEmpty, "idle reentrant cancel expires completion even without a new ID")

        let cleanupDriver = FakeVoiceDriver()
        let cleanupMachine = VoiceInputStateMachine(driver: cleanupDriver, now: { clock })
        var cleanupFinals: [String] = []
        cleanupMachine.onFinal = { cleanupFinals.append($0) }
        cleanupMachine.begin(gestureStartedAt: clock)
        let cleanupOld = cleanupDriver.starts.last!
        clock += 1
        cleanupMachine.release()
        cleanupDriver.onCancel = {
            cleanupDriver.onCancel = nil
            cleanupMachine.begin(gestureStartedAt: clock)
        }
        cleanupDriver.emit(.final("old"), for: cleanupOld)
        check(cleanupFinals.isEmpty && cleanupDriver.starts.last != cleanupOld,
              "driver cleanup reentry also suppresses old final")
        check(cleanupMachine.state == .listening(partial: "", cancelArmed: false, elapsed: 0),
              "driver cleanup reentry does not overwrite new state")

        let replaceDriver = FakeVoiceDriver()
        let replaceMachine = VoiceInputStateMachine(driver: replaceDriver, now: { clock })
        replaceMachine.begin(gestureStartedAt: clock)
        var replacementFromObserver = false
        replaceMachine.onStateChange = { state in
            if state == .idle && !replacementFromObserver {
                replacementFromObserver = true
                replaceMachine.begin(gestureStartedAt: clock)
            }
        }
        replaceMachine.begin(gestureStartedAt: clock)
        check(replacementFromObserver && replaceDriver.starts.count == 2,
              "outer begin does not overwrite observer's newer session")
        check(replaceMachine.state == .listening(partial: "", cancelArmed: false, elapsed: 0),
              "observer's newer session remains listening")

        let timeoutDriver = FakeVoiceDriver()
        let timeoutMachine = VoiceInputStateMachine(driver: timeoutDriver, now: { clock })
        timeoutMachine.begin(gestureStartedAt: clock)
        let timeoutOld = timeoutDriver.starts.last!
        clock += 1
        timeoutMachine.release()
        timeoutDriver.onCancel = {
            timeoutDriver.onCancel = nil
            timeoutMachine.begin(gestureStartedAt: clock)
        }
        clock += 6
        timeoutMachine.tick()
        check(timeoutDriver.starts.last != timeoutOld && timeoutMachine.state == .listening(partial: "", cancelArmed: false, elapsed: 0),
              "timeout cleanup reentry cannot overwrite a new session")

        let deniedAudio = VoiceAudioLeaseSlot(coordinator: UnavailableVoiceAudioCoordinator())
        check(!deniedAudio.acquire(onRevoked: {}) && !deniedAudio.activateForRecording(),
              "default coordinator fails closed")
        let coordinator = FakeAudioCoordinator()
        let slot = VoiceAudioLeaseSlot(coordinator: coordinator)
        let leaseA = FakeAudioLease()
        coordinator.next = { leaseA }
        var revocations = 0
        check(slot.acquire(onRevoked: { revocations += 1 }), "coordinator can grant a lease")
        check(slot.activateForRecording() && leaseA.activationCount == 1, "activation uses granted lease")
        slot.release(); slot.release()
        check(leaseA.releaseCount == 1, "repeated release transfers ownership only once")
        coordinator.callbacks[0]()
        check(revocations == 0, "released lease cannot revoke later")

        let leaseB = FakeAudioLease()
        coordinator.next = { leaseB }
        check(slot.acquire(onRevoked: { revocations += 1; slot.release() }), "new lease after release")
        coordinator.callbacks[0]()
        check(leaseB.releaseCount == 0 && revocations == 0, "stale callback cannot release new lease")
        coordinator.callbacks[1]()
        coordinator.callbacks[1]()
        check(leaseB.releaseCount == 1 && revocations == 1, "current revocation releases and reports once")
        check(!slot.activateForRecording(), "revoked lease cannot activate")

        let leaseOrder = FakeAudioLease()
        coordinator.next = { leaseOrder }
        var order: [String] = []
        leaseOrder.onRelease = { order.append("released") }
        check(slot.acquire(onRevoked: {
            order.append("stop-start")
            coordinator.callbacks.last?() // synchronous duplicate revocation
            order.append("stopped")
            slot.release() // driver cleanup releases after stopping the engine
        }), "lease for double-revocation ordering acquired")
        coordinator.callbacks.last?()
        coordinator.callbacks.last?()
        check(order == ["stop-start", "stopped", "released"] && leaseOrder.releaseCount == 1,
              "synchronous double revocation stops before exactly one release")

        let leaseUnacked = FakeAudioLease()
        coordinator.next = { leaseUnacked }
        check(slot.acquire(onRevoked: { order.append("unacknowledged") }), "unacknowledged lease acquired")
        coordinator.callbacks.last?()
        check(leaseUnacked.releaseCount == 0 && !slot.activateForRecording() && !slot.acquire(onRevoked: {}),
              "unacknowledged revocation holds fence and blocks reuse")
        slot.release()
        check(leaseUnacked.releaseCount == 1, "explicit post-stop release returns fence")

        let leaseC = FakeAudioLease()
        leaseC.activationResult = false
        coordinator.next = { leaseC }
        check(slot.acquire(onRevoked: { revocations += 1 }), "activation-failure lease acquired")
        check(!slot.activateForRecording() && leaseC.releaseCount == 1, "failed activation releases once")
        slot.release()
        check(leaseC.releaseCount == 1, "cleanup after failed activation is harmless")

        let leasePending = FakeAudioLease()
        coordinator.next = { leasePending }
        var nestedPendingAcquire = true
        coordinator.duringAcquire = { nestedPendingAcquire = slot.acquire(onRevoked: {}) }
        check(slot.acquire(onRevoked: {}) && !nestedPendingAcquire,
              "reentrant acquire cannot overlap a pending acquisition")
        coordinator.duringAcquire = nil
        slot.release()
        check(leasePending.releaseCount == 1, "pending acquisition is released exactly once")

        let leaseD = FakeAudioLease()
        coordinator.next = { leaseD }
        coordinator.duringAcquire = { coordinator.callbacks.last?() }
        check(!slot.acquire(onRevoked: { revocations += 1 }), "synchronous revocation rejects acquisition")
        check(leaseD.releaseCount == 1 && revocations == 2, "synchronously revoked returned lease is released")
        coordinator.duringAcquire = nil

        let leaseE = FakeAudioLease()
        coordinator.next = { leaseE }
        check(slot.acquire(onRevoked: { revocations += 1; slot.release() }), "reentrant activation lease acquired")
        leaseE.onActivate = { coordinator.callbacks.last?() }
        check(!slot.activateForRecording() && leaseE.releaseCount == 1 && revocations == 3,
              "activation revocation cannot leave a valid lease")

        let leaseF = FakeAudioLease()
        let leaseG = FakeAudioLease()
        coordinator.next = { leaseF }
        check(slot.acquire(onRevoked: { revocations += 1 }), "lease for release reentry acquired")
        var nestedLeaseAcquired = false
        leaseF.onRelease = {
            leaseF.onRelease = nil
            coordinator.next = { leaseG }
            nestedLeaseAcquired = slot.acquire(onRevoked: { revocations += 1 })
        }
        check(!slot.acquire(onRevoked: { revocations += 1 }) && !nestedLeaseAcquired,
              "acquire never implicitly releases an active lease")
        slot.release()
        check(nestedLeaseAcquired, "release can synchronously install a new lease")
        check(slot.activateForRecording() && leaseG.activationCount == 1 && leaseG.releaseCount == 0,
              "newer reentrant lease retains ownership")
        slot.release()
        check(leaseF.releaseCount == 1 && leaseG.releaseCount == 1, "reentrant leases each released once")

        coordinator.next = { nil }
        check(!slot.acquire(onRevoked: { revocations += 1 }), "coordinator may deny")
        coordinator.callbacks.last?()
        check(revocations == 3, "callback after denied acquisition ignored")
        print("PASS VoiceInput: \(assertions) assertions; pure state machine and fake driver only")
    }
}
