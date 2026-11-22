import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Pure, Release-compatible experiment switches; they never enable themselves.
struct ChatLayoutExperiments {
    let allEager: Bool
    let skipAutoScroll: Bool
    static let current = Self(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        let enabled = hasUniqueLayoutDiagnostics(arguments: arguments)
        allEager = enabled && arguments.contains("-WoowLayoutAllEager")
        skipAutoScroll = enabled && arguments.contains("-WoowLayoutSkipAutoScroll")
    }
}

/// Ambiguous duplicate switches fail closed for both logging and experiments.
private func hasUniqueLayoutDiagnostics(arguments: [String]) -> Bool {
    let switches = ["-WoowLayoutDiagnostics", "-WoowLayoutAllEager", "-WoowLayoutSkipAutoScroll"]
    return arguments.filter { $0 == switches[0] }.count == 1
        && switches.dropFirst().allSatisfy { flag in arguments.filter { $0 == flag }.count <= 1 }
}

/// Temporary, opt-in observation only. Available in Release; never publishes UI state.
/// Only a send tap arms a round. Hot events share ONE 250 ms output budget, with
/// cumulative begin/end counts and the latest numeric sample per event. A delayed
/// flush retains a final end event even when no more layout callbacks arrive.
/// Large batches drain across hot slots, never as multiple lines in one slot.
@MainActor
final class ChatLayoutDiagnostics {
    enum Event: String, CaseIterable {
        case sendTap, dismissKeyboardBegin, dismissKeyboardEnd, sendAttemptBegin, sendAttemptEnd
        case keyboardWillFrame, keyboardDidFrame, keyboardWillHide, keyboardDidHide
        case columnFrame, containerInset, reservePadding, transcriptLayout, transcriptPosition
        case submittingChanged
        case scrollGeometryBegin, scrollGeometryEnd, scrollConversationBegin, scrollConversationEnd
        case scrollSubmittingBegin, scrollSubmittingEnd, scrollRequestBegin, scrollRequestEnd
        case endTurnBegin, endTurnEnd, archiveTurnBegin, archiveTurnEnd, archiveSaveBegin, archiveSaveEnd
        case appendBegin, appendEnd, previewClearBegin, previewClearEnd, finishBegin, finishEnd

        fileprivate var isHot: Bool {
            switch self {
            case .keyboardWillFrame, .keyboardDidFrame, .keyboardWillHide, .keyboardDidHide,
                 .columnFrame, .containerInset, .reservePadding, .transcriptLayout,
                 .transcriptPosition, .submittingChanged, .scrollGeometryBegin, .scrollGeometryEnd,
                 .scrollConversationBegin, .scrollConversationEnd, .scrollSubmittingBegin,
                 .scrollSubmittingEnd, .scrollRequestBegin, .scrollRequestEnd: return true
            default: return false
            }
        }
    }

    // Closed vocabulary: no text, identifiers, errors, URLs or arbitrary field names.
    enum Field: String, CaseIterable {
        case allEager, skipAutoScroll
        case entries, revision, submitting, preview, editing, panel, lazyEnd
        case docked, keyboardTop, keyboardHeight, hiding, did, local, changed, duration
        case frameBottom, frameHeight, previousBottom, reportedBottom, reserve, padding, replaced
        case contentHeight, bottomY, viewportHeight, following, success, archiveAvailable
    }

    enum Value {
        case number(Double), count(UInt64), flag(Bool)

        fileprivate var json: Any? {
            switch self {
            case .number(let value): return value.isFinite ? value : nil
            case .count(let value): return value
            case .flag(let value): return value
            }
        }
    }

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "io.woowtech.assistant.layout", category: "diagnostics")
    #endif
    static let shared = ChatLayoutDiagnostics(arguments: ProcessInfo.processInfo.arguments,
        now: { ProcessInfo.processInfo.systemUptime }, emit: { line in
            #if canImport(OSLog)
            logger.notice("\(line, privacy: .public)")
            #endif
        })

    private struct Sample {
        var count: UInt64
        var time: Double
        var fields: [Field: Value]
    }
    private let enabled: Bool
    private let now: () -> Double
    private let emit: (String) -> Void
    private let schedulesFlush: Bool
    private var started: Double?
    private var round: UInt64 = 0
    private var records = 0
    private var lastHot: Double?
    private var samples: [Event: Sample] = [:]
    // First-dirtied order prevents a busy event from starving another event's end.
    private var dirty: [Event] = []
    private var flushTask: Task<Void, Never>?
    // The observed relay adds 116 bytes of prefix/suffix: <=885 with newline.
    // Keep headroom below 900, without relying on a particular OSLog truncation limit.
    private static let maximumRecordBytes = 768

    // Clock/sink injection keeps rate, privacy and Release checks independent of OSLog.
    init(arguments: [String], now: @escaping () -> Double, emit: @escaping (String) -> Void,
         schedulesFlush: Bool = true) {
        enabled = hasUniqueLayoutDiagnostics(arguments: arguments)
        self.now = now
        self.emit = emit
        self.schedulesFlush = schedulesFlush
    }

    func beginSend(fields: @autoclosure () -> [Field: Value]) {
        guard enabled else { return }
        flushTask?.cancel(); flushTask = nil
        started = now()
        round &+= 1
        records = 0
        lastHot = nil
        samples.removeAll(keepingCapacity: true)
        dirty.removeAll(keepingCapacity: true)
        record(.sendTap, fields: fields())
    }

    func record(_ event: Event, fields: @autoclosure () -> [Field: Value] = [:]) {
        guard let time = activeTime() else { return }
        if event.isHot {
            samples[event] = Sample(count: (samples[event]?.count ?? 0) + 1, time: time, fields: fields())
            if !dirty.contains(event) { dirty.append(event) }
            flushHot(at: time)
        } else {
            write(["event": event.rawValue, "fields": Self.json(fields())], at: time)
        }
    }

    /// Also used with a fake clock in focused checks. Does not arm/reset a round.
    func flushPendingHot() {
        guard let time = activeTime() else { return }
        flushHot(at: time)
    }

    private func activeTime() -> Double? {
        guard enabled, let started, records < 300 else { return nil }
        let time = now()
        guard time.isFinite, time >= started, time - started < 60 else {
            self.started = nil
            flushTask?.cancel(); flushTask = nil
            return nil
        }
        return time
    }

    private func flushHot(at time: Double) {
        guard !dirty.isEmpty else { return }
        let remaining = 0.25 - (time - (lastHot ?? (time - 0.25)))
        guard remaining <= 0 else {
            if schedulesFlush, flushTask == nil {
                let expectedRound = round
                flushTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(ceil(remaining * 1_000_000_000))) }
                    catch { return }
                    guard let self, self.round == expectedRound else { return }
                    self.flushTask = nil
                    self.flushPendingHot()
                }
            }
            return
        }
        flushTask?.cancel(); flushTask = nil
        var events: [String: Any] = [:]
        for event in dirty {
            guard let sample = samples[event] else { continue }
            let fields = Self.json(sample.fields)
            var value: [String: Any] = ["count": sample.count, "t": sample.time, "fields": fields]
            var candidate = events
            candidate[event.rawValue] = value
            if (encoded(["event": "hot", "events": candidate], at: time)?.count ?? Int.max) > Self.maximumRecordBytes {
                if !events.isEmpty { break }
                // Defensive fallback for a single unusually large sample. Preserve
                // event/count/time and explicitly report omitted fields, never truncate JSON.
                value["fields"] = [String: Any]()
                value["fieldsOmitted"] = fields.count
            }
            events[event.rawValue] = value
        }
        dirty.removeFirst(events.count)
        lastHot = time
        write(["event": "hot", "events": events], at: time)
        // Only schedules the next slot; the shared 250 ms guard still applies.
        if !dirty.isEmpty, records < 300 { flushHot(at: time) }
    }

    private static func json(_ fields: [Field: Value]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (field, value) in fields { result[field.rawValue] = value.json }
        return result
    }

    private func encoded(_ payload: [String: Any], at time: Double) -> Data? {
        var payload = payload
        payload["t"] = time
        payload["round"] = round
        payload["seq"] = records + 1
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func write(_ payload: [String: Any], at time: Double) {
        guard records < 300 else { return }
        var payload = payload
        var data = encoded(payload, at: time)
        if (data?.count ?? Int.max) > Self.maximumRecordBytes, let fields = payload["fields"] as? [String: Any] {
            payload["fields"] = [String: Any]()
            payload["fieldsOmitted"] = fields.count
            data = encoded(payload, at: time)
        }
        guard let data, data.count <= Self.maximumRecordBytes,
              let line = String(data: data, encoding: .utf8) else { return }
        records += 1
        emit(line)
        if records == 300 { flushTask?.cancel(); flushTask = nil }
    }
}
