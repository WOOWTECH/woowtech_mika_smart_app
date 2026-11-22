import Foundation

@main
enum CheckChatLayoutDiagnostics {
    @MainActor
    static func main() async throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool) {
            precondition(condition())
            assertions += 1
        }
        func decode(_ line: String) -> [String: Any] {
            try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        }
        var time = 100.0
        var clockReads = 0
        var fieldsRead = false
        func fields() -> [ChatLayoutDiagnostics.Field: ChatLayoutDiagnostics.Value] {
            fieldsRead = true
            return [.entries: .count(14)]
        }
        var lines: [String] = []
        // Neither a lookalike flag nor default-off may read the clock/evaluate fields.
        for arguments in [[], ["-WoowLayoutDiagnosticsExtra"], ["-WoowLayoutDiagnostics=false"]] {
            let disabled = ChatLayoutDiagnostics(arguments: arguments,
                now: { clockReads += 1; return time }, emit: { lines.append($0) })
            disabled.beginSend(fields: fields())
            disabled.record(.columnFrame, fields: fields())
            disabled.flushPendingHot()
        }
        expect(clockReads == 0 && !fieldsRead && lines.isEmpty)
        let probe = ChatLayoutDiagnostics(arguments: ["-WoowLayoutDiagnostics", "PRIVATE_SENTINEL"],
            now: { clockReads += 1; return time }, emit: { lines.append($0) }, schedulesFlush: false)
        probe.record(.finishBegin, fields: fields())
        probe.flushPendingHot()
        expect(clockReads == 0 && !fieldsRead && lines.isEmpty) // no tap, no round
        probe.beginSend(fields: fields())
        expect(fieldsRead && decode(lines[0])["event"] as? String == "sendTap")

        let pairs: [(ChatLayoutDiagnostics.Event, ChatLayoutDiagnostics.Event)] = [
            (.scrollGeometryBegin, .scrollGeometryEnd), (.scrollConversationBegin, .scrollConversationEnd),
            (.scrollSubmittingBegin, .scrollSubmittingEnd), (.scrollRequestBegin, .scrollRequestEnd)]
        for (begin, end) in pairs { probe.record(begin); probe.record(end) }
        probe.record(.keyboardWillHide, fields: [.hiding: .flag(true)])
        probe.record(.keyboardDidHide, fields: [.docked: .flag(false)])
        expect(lines.count == 2) // shared hot budget, not a separate budget for each event
        time = 100.249
        probe.flushPendingHot()
        expect(lines.count == 2)
        time = 100.25
        probe.flushPendingHot()
        expect(lines.count == 3)
        var counts: [String: UInt64] = [:]
        for line in lines {
            for (event, value) in decode(line)["events"] as? [String: [String: Any]] ?? [:] {
                counts[event] = (value["count"] as? NSNumber)?.uint64Value
            }
        }
        for (begin, end) in pairs {
            expect(counts[begin.rawValue] == 1 && counts[end.rawValue] == 1)
        }
        expect(counts["keyboardWillHide"] == 1 && counts["keyboardDidHide"] == 1)
        for _ in 0..<5_000 { probe.record(.scrollGeometryBegin); probe.record(.scrollGeometryEnd) }
        expect(lines.count == 3)
        time = 100.5
        probe.flushPendingHot()
        let burst = decode(lines.last!)["events"] as! [String: [String: Any]]
        expect((burst["scrollGeometryBegin"]?["count"] as? NSNumber)?.intValue == 5_001)
        expect((burst["scrollGeometryEnd"]?["count"] as? NSNumber)?.intValue == 5_001)
        let hotTimes = lines.map(decode).filter { $0["event"] as? String == "hot" }.map { $0["t"] as! Double }
        expect(zip(hotTimes, hotTimes.dropFirst()).allSatisfy { $1 - $0 >= 0.25 })

        // Critical synchronous stages survive a saturated hot path.
        let phases: [ChatLayoutDiagnostics.Event] = [.endTurnBegin, .archiveTurnBegin, .archiveSaveBegin,
            .archiveSaveEnd, .archiveTurnEnd, .appendBegin, .appendEnd, .finishBegin, .finishEnd, .endTurnEnd]
        for event in phases { probe.record(event) }
        expect(lines.suffix(phases.count).map { decode($0)["event"] as! String } == phases.map(\.rawValue))
        probe.record(.appendEnd, fields: [.entries: .count(.max), .submitting: .flag(false),
            .frameBottom: .number(.nan), .padding: .number(.infinity), .reserve: .number(-.infinity),
            .keyboardTop: .number(400.5)])
        let safe = decode(lines.last!)["fields"] as! [String: Any]
        expect(Set(safe.keys) == Set(["entries", "submitting", "keyboardTop"]))
        expect((safe["entries"] as? NSNumber)?.uint64Value == .max)
        expect(safe["submitting"] as? Bool == false && safe["keyboardTop"] as? Double == 400.5)
        expect(!lines.joined().contains("PRIVATE_SENTINEL"))
        // No dynamic string values may pass the wire format, even inside samples.
        let eventNames = Set(ChatLayoutDiagnostics.Event.allCases.map(\.rawValue) + ["hot"])
        func checkValues(_ object: Any, key: String = "") -> Bool {
            if let value = object as? String { return key == "event" && eventNames.contains(value) }
            if let dict = object as? [String: Any] { return dict.allSatisfy { checkValues($0.value, key: $0.key) } }
            return object is NSNumber
        }
        expect(lines.map(decode).allSatisfy { checkValues($0) })

        time = 159.999
        probe.record(.finishEnd)
        let beforeExpiry = lines.count
        time = 160
        probe.record(.finishBegin, fields: fields())
        probe.record(.columnFrame)
        probe.flushPendingHot()
        expect(lines.count == beforeExpiry)
        time = 170
        probe.record(.columnFrame)
        expect(lines.count == beforeExpiry) // callbacks cannot rearm expired rounds
        probe.beginSend(fields: [:])
        let secondStart = lines.count - 1
        for _ in 0..<400 { probe.record(.appendBegin) }
        expect(lines.count - secondStart == 300)
        expect(decode(lines.last!)["seq"] as? Int == 300)
        let readsAtLimit = clockReads
        fieldsRead = false
        probe.record(.columnFrame, fields: fields())
        expect(clockReads == readsAtLimit && !fieldsRead)
        probe.beginSend(fields: [:])
        expect(decode(lines.last!)["seq"] as? Int == 1 && decode(lines.last!)["round"] as? Int == 3)
        probe.record(.scrollGeometryBegin)
        let reset = decode(lines.last!)["events"] as! [String: [String: Any]]
        expect((reset["scrollGeometryBegin"]?["count"] as? NSNumber)?.intValue == 1)

        // Real scheduler: preserve a final end with no subsequent UI callback.
        var scheduled: [String] = []
        let live = ChatLayoutDiagnostics(arguments: ["-WoowLayoutDiagnostics"],
            now: { ProcessInfo.processInfo.systemUptime }, emit: { scheduled.append($0) })
        live.beginSend(fields: [:])
        live.record(.scrollRequestBegin)
        live.record(.scrollRequestEnd)
        try await Task.sleep(nanoseconds: 600_000_000)
        expect(scheduled.count == 3)
        expect((decode(scheduled.last!)["events"] as? [String: Any])?["scrollRequestEnd"] != nil)
        // A new tap cancels the previous round's pending flush.
        live.record(.scrollGeometryBegin)
        live.record(.scrollGeometryEnd)
        live.beginSend(fields: [:])
        let afterReset = scheduled.count
        try await Task.sleep(nanoseconds: 600_000_000)
        expect(scheduled.count == afterReset)
        print("{\"assertions\":\(assertions)}")
    }
}
