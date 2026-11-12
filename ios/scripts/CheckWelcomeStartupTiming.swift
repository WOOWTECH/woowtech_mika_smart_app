import Foundation

@main enum CheckWelcomeStartupTiming {
    @MainActor static func main() {
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool) { precondition(value()); assertions += 1 }
        var now = 10.0
        var events: [(WelcomeStartupTiming.Event, Int)] = []
        let timing = WelcomeStartupTiming(enabled: true, clock: { now }, emit: { events.append(($0, $1)) })
        let value = timing.measure(.chatInitStart, .chatInitEnd) { () -> Int in now = 10.125; return 7 }
        expect(value == 7)
        expect(events.count == 2 && events[0].0 == .chatInitStart && events[0].1 == 0)
        expect(events[1].0 == .chatInitEnd && events[1].1 == 125)
        now = 11; timing.mark(.welcomeAppeared); timing.mark(.welcomeAppeared)
        expect(events.count == 3 && events[2].1 == 1000)
        now = 9; timing.mark(.rootAppeared)
        now = .nan; timing.mark(.rootAppeared)
        expect(events.count == 3)
        now = 12; timing.mark(.rootAppeared)
        expect(events.count == 4 && events[3].0 == .rootAppeared && events[3].1 == 2000)
        timing.recordWake(expected: 20, actual: 20.49)
        expect(events.count == 4)
        timing.recordWake(expected: 20, actual: 21)
        expect(events.count == 5 && events[4].0 == .mainLoopDelay && events[4].1 == 1000)
        timing.recordWake(expected: .nan, actual: 30)
        timing.mark(.mainLoopDelay)
        expect(events.count == 5)
        let disabled = WelcomeStartupTiming(enabled: false, clock: { fatalError("disabled must not read clock") },
                                            emit: { _, _ in fatalError("disabled must not emit") })
        expect(disabled.measure(.chatInitStart, .chatInitEnd) { 9 } == 9)
        disabled.mark(.welcomeAppeared); disabled.recordWake(expected: 0, actual: 100); disabled.startHeartbeat()
        expect(events.count == 5)
        print("WELCOME_STARTUP_TIMING assertions=\(assertions) status=PASS")
    }
}
