import Foundation

@MainActor
final class ChatFakeDriver: VoiceInputDriver {
    var callbacks: [UUID: (UUID, VoiceInputEvent) -> Void] = [:]
    var current: UUID!
    var cancelled: [UUID] = []
    var finished: [UUID] = []
    func start(id: UUID, emit: @escaping (UUID, VoiceInputEvent) -> Void) { current = id; callbacks[id] = emit }
    func finish(id: UUID) { finished.append(id) }
    func cancel(id: UUID) { cancelled.append(id) }
    func emit(_ event: VoiceInputEvent, _ id: UUID) { callbacks[id]?(id, event) }
}

@main struct ChatVoiceChecks {
    @MainActor static func main() {
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
        print("PASS ChatVoice composer semantics (fake driver; no Apple SDK)")
    }
}
