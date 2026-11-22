import Foundation

@main
enum CheckChatLayoutDiagnostics {
    @MainActor
    static func hotBurst() -> [String] {
        var time = 239844.44127766669
        var lines: [String] = []
        let probe = ChatLayoutDiagnostics(arguments: ["-WoowLayoutDiagnostics"],
            now: { time }, emit: { lines.append($0) }, schedulesFlush: false)
        probe.beginSend(fields: [:])
        probe.record(.transcriptLayout) // consume the first hot slot
        let fields: [ChatLayoutDiagnostics.Field: ChatLayoutDiagnostics.Value] = [
            .entries: .count(15), .revision: .count(3), .submitting: .flag(true),
            .preview: .flag(false), .following: .flag(true)]
        for event: ChatLayoutDiagnostics.Event in [
            .scrollGeometryBegin, .scrollGeometryEnd, .scrollConversationBegin, .scrollConversationEnd,
            .scrollSubmittingBegin, .scrollSubmittingEnd, .scrollRequestBegin, .scrollRequestEnd] {
            probe.record(event, fields: fields)
        }
        probe.record(.reservePadding, fields: [
            .frameBottom: .number(852), .frameHeight: .number(765), .docked: .flag(true),
            .keyboardTop: .number(468), .reportedBottom: .number(34), .replaced: .flag(false),
            .reserve: .number(384), .padding: .number(384)])
        for _ in 0..<12 { time += 0.25; probe.flushPendingHot() }
        return lines
    }

    @MainActor
    static func main() async throws {
        if ProcessInfo.processInfo.arguments.contains("--measure-hot-size") {
            let lines = hotBurst()
            print("{\"max_record_bytes\":\(lines.map { $0.utf8.count }.max()!),\"records\":\(lines.count)}")
            return
        }
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool) {
            precondition(condition())
            assertions += 1
        }
        func decode(_ line: String) -> [String: Any] {
            try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        }
        let switches = ["-WoowLayoutDiagnostics", "-WoowLayoutAllEager", "-WoowLayoutSkipAutoScroll"]
        // Every combination, including each standalone experiment and both without the primary.
        for mask in 0..<8 {
            let arguments = switches.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil }
            let experiments = ChatLayoutExperiments(arguments: arguments)
            expect(experiments.allEager == (mask & 1 != 0 && mask & 2 != 0))
            expect(experiments.skipAutoScroll == (mask & 1 != 0 && mask & 4 != 0))
        }
        for duplicate in switches {
            let experiments = ChatLayoutExperiments(arguments: switches + [duplicate])
            expect(!experiments.allEager && !experiments.skipAutoScroll)
        }
        for primary in ["--WoowLayoutDiagnostics", "-WoowLayoutDiagnostics=true", "-WoowLayoutDiagnostics "] {
            let experiments = ChatLayoutExperiments(arguments: [primary] + Array(switches.dropFirst()))
            expect(!experiments.allEager && !experiments.skipAutoScroll)
        }
        let lookalikes = ChatLayoutExperiments(arguments: [switches[0], "-WoowLayoutAllEager=true",
            "-WoowLayoutSkipAutoScrollExtra"])
        expect(!lookalikes.allEager && !lookalikes.skipAutoScroll)
        let reordered = ChatLayoutExperiments(arguments: ["ignored", switches[2], switches[1], switches[0]])
        expect(reordered.allEager && reordered.skipAutoScroll)
        var time = 100.0
        var clockReads = 0
        var fieldsRead = false
        func fields() -> [ChatLayoutDiagnostics.Field: ChatLayoutDiagnostics.Value] {
            fieldsRead = true
            return [.entries: .count(14)]
        }
        var lines: [String] = []
        // Neither a lookalike flag nor default-off may read the clock/evaluate fields.
        let disabledArguments = [[], ["-WoowLayoutDiagnosticsExtra"], ["-WoowLayoutDiagnostics=false"],
            [switches[1]], [switches[2]], Array(switches.dropFirst())] + switches.map { switches + [$0] }
        for arguments in disabledArguments {
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
        probe.record(.sendAttemptEnd, fields: [.allEager: .flag(true), .skipAutoScroll: .flag(false)])
        let experimentFields = decode(lines.last!)["fields"] as! [String: Any]
        expect(experimentFields["allEager"] as? Bool == true && experimentFields["skipAutoScroll"] as? Bool == false)

        // Nine realistic events used to form one 1425-byte record on this host.
        // Drain across slots with valid JSON, complete event coverage and original timestamps.
        let paged = hotBurst()
        let maximumBytes = paged.map { $0.utf8.count }.max()!
        expect(maximumBytes <= 768)
        expect(paged.allSatisfy { $0.utf8.count + 116 + 1 < 900 })
        let pages = paged.map(decode)
        expect(pages.enumerated().allSatisfy { $0.element["seq"] as? Int == $0.offset + 1 })
        let hotPages = pages.filter { $0["event"] as? String == "hot" }
        expect(hotPages.count > 2)
        let pageTimes = hotPages.map { $0["t"] as! Double }
        expect(zip(pageTimes, pageTimes.dropFirst()).allSatisfy { $1 - $0 >= 0.25 })
        var delivered: [String: [String: Any]] = [:]
        for page in hotPages {
            for (event, value) in page["events"] as! [String: [String: Any]] { delivered[event] = value }
        }
        for (begin, end) in pairs {
            expect(delivered[begin.rawValue]?["count"] as? Int == 1 && delivered[end.rawValue]?["count"] as? Int == 1)
            expect((delivered[end.rawValue]?["fields"] as? [String: Any])?["entries"] as? Int == 15)
        }
        expect(delivered.count == 10) // initial layout plus nine queued events
        expect(delivered.values.allSatisfy { $0["t"] as? Double == 239844.44127766669 && $0["fieldsOmitted"] == nil })
        expect((delivered["reservePadding"]?["fields"] as? [String: Any])?["padding"] as? Int == 384)
        expect(pages.allSatisfy { checkValues($0) })

        var queueTime = 0.0
        var queuedLines: [String] = []
        let queued = ChatLayoutDiagnostics(arguments: ["-WoowLayoutDiagnostics"],
            now: { queueTime }, emit: { queuedLines.append($0) }, schedulesFlush: false)
        let queuedEvents = pairs.flatMap { [$0.0, $0.1] } + [.reservePadding]
        queued.beginSend(fields: [:])
        queued.record(.transcriptLayout)
        // Update every queued event repeatedly: preserve latest fields and cumulative counts,
        // without moving busy events ahead of events waiting since an earlier slot.
        for step in 0..<20 {
            for event in queuedEvents {
                queued.record(event, fields: [.entries: .count(UInt64(step)),
                    .revision: .count(4), .following: .flag(false), .submitting: .flag(false)])
            }
            queueTime += 0.25
        }
        let earlyEvents = Set(queuedLines.map(decode).filter { ($0["t"] as? Double ?? 0) <= 1.5 }
            .flatMap { Array(($0["events"] as? [String: Any] ?? [:]).keys) })
        expect(Set(queuedEvents.map(\.rawValue)).isSubset(of: earlyEvents))
        for _ in 0..<12 { queueTime += 0.25; queued.flushPendingHot() }
        var latest: [String: [String: Any]] = [:]
        for line in queuedLines {
            for (event, value) in decode(line)["events"] as? [String: [String: Any]] ?? [:] { latest[event] = value }
        }
        expect(queuedEvents.allSatisfy {
            latest[$0.rawValue]?["count"] as? Int == 20
                && (latest[$0.rawValue]?["fields"] as? [String: Any])?["entries"] as? Int == 19
        })
        expect(queuedLines.allSatisfy { $0.utf8.count <= 768 })
        let queuedTimes = queuedLines.map(decode).filter { $0["event"] as? String == "hot" }.map { $0["t"] as! Double }
        expect(zip(queuedTimes, queuedTimes.dropFirst()).allSatisfy { $1 - $0 >= 0.25 })
        let noPending = queuedLines.count
        queued.flushPendingHot()
        expect(queuedLines.count == noPending)
        queueTime = 59.9
        for event in queuedEvents { queued.record(event) }
        let beforeQueuedExpiry = queuedLines.count
        queueTime = 60
        queued.flushPendingHot()
        expect(queuedLines.count == beforeQueuedExpiry) // pending pages cannot outlive the round
        queued.beginSend(fields: [:])
        let cappedStart = queuedLines.count - 1
        for event in queuedEvents { queued.record(event) }
        for _ in 0..<400 { queued.record(.appendEnd) }
        queueTime += 1
        queued.flushPendingHot()
        expect(queuedLines.count - cappedStart == 300) // pending pages cannot overrun the total cap

        // Every legal field with extreme finite values: a single oversized sample
        // keeps phase/count/time, explicitly counts omitted fields and stays valid JSON.
        let huge = Dictionary(uniqueKeysWithValues: ChatLayoutDiagnostics.Field.allCases.map {
            ($0, ChatLayoutDiagnostics.Value.number(.greatestFiniteMagnitude))
        })
        queued.beginSend(fields: huge)
        let hugePhase = decode(queuedLines.last!)
        expect(hugePhase["fieldsOmitted"] as? Int == huge.count)
        expect((hugePhase["fields"] as? [String: Any])?.isEmpty == true)
        queued.record(.reservePadding, fields: huge)
        let hugeSample = (decode(queuedLines.last!)["events"] as! [String: [String: Any]])["reservePadding"]!
        expect(hugeSample["count"] as? Int == 1 && hugeSample["fieldsOmitted"] as? Int == huge.count)
        expect(queuedLines.allSatisfy { $0.utf8.count <= 768 })

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
        live.record(.transcriptLayout)
        for event in queuedEvents {
            live.record(event, fields: [.entries: .count(15), .revision: .count(3), .submitting: .flag(true),
                .preview: .flag(false), .following: .flag(true)])
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let livePages = scheduled.dropFirst(afterReset).map(decode)
        let liveEvents = Set(livePages.flatMap { Array(($0["events"] as? [String: Any] ?? [:]).keys) })
        expect(Set(queuedEvents.map(\.rawValue)).isSubset(of: liveEvents))
        var finalCounts: [String: Int] = [:]
        for page in livePages {
            for (event, sample) in page["events"] as? [String: [String: Any]] ?? [:] {
                finalCounts[event] = sample["count"] as? Int
            }
        }
        expect(queuedEvents.allSatisfy { finalCounts[$0.rawValue] == 1 })
        expect(scheduled.allSatisfy { $0.utf8.count <= 768 })
        let allLines = lines + queuedLines + scheduled + paged
        let maximumEmittedBytes = allLines.map { $0.utf8.count }.max()!
        expect(maximumEmittedBytes <= 768)
        print("{\"assertions\":\(assertions),\"max_record_bytes\":\(maximumBytes),\"burst_records\":\(paged.count),"
            + "\"max_emitted_record_bytes\":\(maximumEmittedBytes),\"delayed_final_events\":\(queuedEvents.count)}")
    }
}
