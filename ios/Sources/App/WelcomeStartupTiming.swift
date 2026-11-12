import Foundation

/// Opt-in, process-local diagnostic. Events are fixed names and elapsed times;
/// never record model settings, conversation contents, URLs or device IDs.
@MainActor final class WelcomeStartupTiming {
    enum Event: String, CaseIterable {
        case chatInitStart, chatInitEnd, mcpInitStart, mcpInitEnd
        case browserInitStart, browserInitEnd, rootAppeared, chatAppeared
        case headerAppeared, composerAppeared, welcomeAppeared
        case viewportInvalid, viewportValid, viewportOverflow, tailScrollRequested
        case mainLoopDelay
    }

    static let shared = WelcomeStartupTiming(
        enabled: ProcessInfo.processInfo.arguments.contains("-WelcomeStartupTiming"),
        clock: { ProcessInfo.processInfo.systemUptime },
        emit: { event, milliseconds in
            NSLog("WELCOME_STARTUP event=%@ value_ms=%lld", event.rawValue, Int64(milliseconds))
        })

    private let enabled: Bool
    private let clock: () -> TimeInterval
    private let emit: (Event, Int) -> Void
    private var origin: TimeInterval?
    private var seen: Set<Event> = []
    private var heartbeatStarted = false

    init(enabled: Bool, clock: @escaping () -> TimeInterval,
         emit: @escaping (Event, Int) -> Void) {
        self.enabled = enabled; self.clock = clock; self.emit = emit
    }

    func mark(_ event: Event) {
        guard enabled, event != .mainLoopDelay, !seen.contains(event) else { return }
        let now = clock()
        guard now.isFinite else { return }
        let start = origin ?? now
        guard now >= start, let elapsed = Self.milliseconds(now - start) else { return }
        origin = start; seen.insert(event); emit(event, elapsed)
    }

    func measure<T>(_ start: Event, _ end: Event, _ operation: () -> T) -> T {
        mark(start)
        defer { mark(end) }
        return operation()
    }

    /// Report only the amount of a long main-actor scheduling delay. A wakeup
    /// delay can also reflect suspension or system load, not necessarily App CPU.
    func recordWake(expected: TimeInterval, actual: TimeInterval) {
        guard enabled, expected.isFinite, actual.isFinite, actual - expected >= 0.5,
              let delay = Self.milliseconds(actual - expected) else { return }
        emit(.mainLoopDelay, delay)
    }

    func startHeartbeat() {
        guard enabled, !heartbeatStarted else { return }
        heartbeatStarted = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let started = self.clock()
            guard started.isFinite else { return }
            var expected = started + 0.25
            while self.clock() - started < 65 && !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                let now = self.clock()
                self.recordWake(expected: expected, actual: now)
                expected = now + 0.25
            }
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int? {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) / 1000 else { return nil }
        return Int(seconds * 1000)
    }
}
