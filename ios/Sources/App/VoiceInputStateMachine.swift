import Foundation

/// The driver and coordinator are called on the main actor. A driver must tag every
/// callback with the ID it was given; callbacks can arrive even after cancellation.
@MainActor
protocol VoiceInputDriver: AnyObject {
    func start(id: UUID, emit: @escaping (UUID, VoiceInputEvent) -> Void)
    func finish(id: UUID)
    func cancel(id: UUID)
}

enum VoiceInputFailure: Equatable {
    case microphoneDenied, speechDenied, speechRestricted, unavailable, audio, recognition, timeout
}

enum VoiceInputEvent: Equatable {
    case partial(String)
    case final(String)
    case failed(VoiceInputFailure)
}

enum VoiceInputState: Equatable {
    case idle
    case listening(partial: String, cancelArmed: Bool, elapsed: TimeInterval)
    case finishing
    case failed(VoiceInputFailure)
    case noMatch
}

/// One press-to-talk gesture. `begin` is called after the UI's long-press
/// threshold, with the time of the original finger-down from the same clock.
/// Call `tick` while active and `cancel` on page/scene changes or interrupted
/// gestures. The driver also needs an independent recording deadline.
@MainActor
final class VoiceInputStateMachine {
    private let driver: VoiceInputDriver
    private let now: () -> TimeInterval
    private let makeID: () -> UUID
    private let minDuration: TimeInterval
    private let maxDuration: TimeInterval
    private let finishTimeout: TimeInterval
    private var id: UUID?
    // Changes even when a reentrant cancellation leaves no active ID.
    private var generation: UInt64 = 0
    private var startedAt: TimeInterval = 0
    private var finishBy: TimeInterval?
    private var pendingFinal: String?
    private var pendingFailure: VoiceInputFailure?

    private(set) var state: VoiceInputState = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((VoiceInputState) -> Void)?
    /// Receives final text once; the caller merges it into the CURRENT draft,
    /// checks conversation identity, and never sends it automatically.
    var onFinal: ((String) -> Void)?

    init(driver: VoiceInputDriver, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         makeID: @escaping () -> UUID = UUID.init, minDuration: TimeInterval = 0.5,
         maxDuration: TimeInterval = 60, finishTimeout: TimeInterval = 5) {
        precondition(minDuration >= 0 && maxDuration > minDuration && finishTimeout > 0)
        self.driver = driver
        self.now = now
        self.makeID = makeID
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.finishTimeout = finishTimeout
    }

    func begin(gestureStartedAt: TimeInterval) {
        let previousGeneration = generation
        cancel()
        // An observer or driver cleanup may have started a newer session.
        guard generation == previousGeneration &+ 1 else { return }
        guard now() - gestureStartedAt < maxDuration else { state = .failed(.timeout); return }
        let newID = makeID()
        id = newID
        startedAt = gestureStartedAt
        pendingFinal = nil
        pendingFailure = nil
        finishBy = nil
        state = .listening(partial: "", cancelArmed: false, elapsed: max(0, now() - startedAt))
        guard id == newID, case .listening = state else { return }
        driver.start(id: newID) { [weak self] id, event in self?.receive(id: id, event: event) }
    }

    func drag(upwardDistance: Double, cancelThreshold: Double) {
        guard case let .listening(partial, _, elapsed) = state else { return }
        state = .listening(partial: partial, cancelArmed: upwardDistance > cancelThreshold, elapsed: elapsed)
    }

    func release() {
        guard let current = id, case let .listening(_, armed, _) = state else { return }
        if armed { cancel(); return }
        if now() - startedAt >= maxDuration {
            guard invalidateAndCancel(current) else { return }
            state = .failed(.timeout)
            return
        }
        if now() - startedAt < minDuration {
            guard invalidateAndCancel(current) else { return }
            state = .noMatch
            return
        }
        if let failure = pendingFailure {
            guard invalidateAndCancel(current) else { return }
            state = .failed(failure)
        } else if let result = pendingFinal {
            complete(result, id: current)
        } else {
            finishBy = now() + finishTimeout
            state = .finishing
            guard id == current, state == .finishing else { return }
            driver.finish(id: current)
        }
    }

    func tick() {
        guard let current = id else { return }
        switch state {
        case let .listening(partial, armed, _):
            let elapsed = max(0, now() - startedAt)
            if elapsed >= maxDuration {
                // A deadline stops capture; it is not the user's release.
                // In particular an early final must never enter the draft yet.
                if armed { cancel() }
                else if invalidateAndCancel(current) { state = .failed(.timeout) }
            }
            else { state = .listening(partial: partial, cancelArmed: armed, elapsed: elapsed) }
        case .finishing:
            if let deadline = finishBy, now() >= deadline {
                guard invalidateAndCancel(current) else { return }
                state = .failed(.timeout)
            }
        default: break
        }
    }

    func cancel() {
        generation &+= 1
        if let current = id {
            guard invalidateAndCancel(current) else { return }
        } else { pendingFinal = nil; pendingFailure = nil; finishBy = nil }
        if state != .idle { state = .idle }
    }

    private func invalidateAndCancel(_ current: UUID) -> Bool {
        // Invalidate first: a synchronous cancellation callback is already stale.
        let cancelledGeneration = generation
        id = nil
        pendingFinal = nil
        pendingFailure = nil
        finishBy = nil
        driver.cancel(id: current)
        return generation == cancelledGeneration && id == nil
    }

    private func receive(id incoming: UUID, event: VoiceInputEvent) {
        guard incoming == id else { return }
        // A delayed timer must not allow a result after the finishing deadline.
        if case .finishing = state, let deadline = finishBy, now() >= deadline {
            guard invalidateAndCancel(incoming) else { return }
            state = .failed(.timeout)
            return
        }
        switch event {
        case .partial(let text):
            guard case let .listening(_, armed, elapsed) = state, pendingFinal == nil, pendingFailure == nil else { return }
            state = .listening(partial: text, cancelArmed: armed, elapsed: elapsed)
        case .final(let text):
            switch state {
            case let .listening(_, armed, elapsed):
                // Even an early final must wait for the finger's cancellation decision.
                guard pendingFinal == nil, pendingFailure == nil else { return }
                pendingFinal = text
                state = .listening(partial: text, cancelArmed: armed, elapsed: elapsed)
            case .finishing: complete(text, id: incoming)
            default: break
            }
        case .failed(let failure):
            guard pendingFinal == nil, pendingFailure == nil else { return }
            if case let .listening(_, armed, _) = state, armed {
                pendingFailure = failure
            } else {
                guard invalidateAndCancel(incoming) else { return }
                state = .failed(failure)
            }
        }
    }

    private func complete(_ text: String, id current: UUID) {
        guard id == current else { return }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        id = nil
        pendingFinal = nil
        pendingFailure = nil
        finishBy = nil
        // A driver cleanup or an idle observer may synchronously cancel or
        // begin another session. Never deliver the old result after either.
        let completionGeneration = generation
        driver.cancel(id: current)
        guard generation == completionGeneration else { return }
        if result.isEmpty { state = .noMatch }
        else {
            state = .idle
            guard generation == completionGeneration else { return }
            onFinal?(result)
        }
    }
}

/// Android's composer appends CJK/full-width boundaries without a space and
/// otherwise inserts one, preserving any whitespace already in the draft.
enum VoiceDraftJoin {
    static func join(_ existing: String, _ spoken: String) -> String {
        guard let left = existing.unicodeScalars.last, let right = spoken.unicodeScalars.first else {
            return existing + spoken
        }
        if CharacterSet.whitespacesAndNewlines.contains(left) { return existing + spoken }
        return existing + (isCJK(left) && isCJK(right) ? "" : " ") + spoken
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x1100...0x11FF).contains(value) || (0x2E80...0x2FFF).contains(value)
            || (0x3000...0x303F).contains(value) || (0x3040...0x30FF).contains(value)
            || (0x3100...0x312F).contains(value) || (0x3130...0x318F).contains(value)
            || (0x31A0...0x31BF).contains(value) || (0x31F0...0x31FF).contains(value)
            || (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
            || (0xA960...0xA97F).contains(value) || (0xAC00...0xD7FF).contains(value)
            || (0xF900...0xFAFF).contains(value) || (0xFF00...0xFFEF).contains(value)
            || (0x20000...0x323AF).contains(value)
    }
}
