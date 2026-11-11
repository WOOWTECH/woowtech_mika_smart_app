import Foundation

@MainActor
final class FakeVoiceDriver: VoiceInputDriver {
    var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var starts: [UUID] = []
    var finishes: [UUID] = []
    var cancellations: [UUID] = []
    var finalOnFinish: String?
    var callbackOnCancel = false
    func start(id: UUID, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        starts.append(id); callbacks[id] = emit
    }
    func finish(id: UUID) {
        finishes.append(id)
        if let finalOnFinish { callbacks[id]?(id, .final(finalOnFinish)) }
    }
    func cancel(id: UUID) {
        cancellations.append(id)
        if callbackOnCancel { callbacks[id]?(id, .final("stale cancellation")) }
    }
    func emit(_ event: VoiceInputEvent, for id: UUID) { callbacks[id]?(id, event) }
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
        check(machine.state == .finishing && driver.finishes.last == long, "maximum duration initiates finish")
        driver.emit(.final(""), for: long)
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
        print("PASS VoiceInput: \(assertions) assertions; pure state machine and fake driver only")
    }
}
