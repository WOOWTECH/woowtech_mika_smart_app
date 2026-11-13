import Foundation

/// AI reply reports against the Play build (964d7bec) and the relay contract
/// (tools/woowtech-relay-worker/src/reports.ts): the exact upload, every
/// delivery and deletion state, and the files left on the device. A scripted
/// transport stands in for the network; nothing here opens a connection.
private struct Failure: Error, CustomStringConvertible { let description: String }

final class Checks {
    var count = 0
    func expect(_ condition: Bool, _ label: String) throws {
        count += 1
        if !condition { throw Failure(description: label) }
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1_794_400_000_000
    var now: Int64 { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ milliseconds: Int64) { lock.lock(); value += milliseconds; lock.unlock() }
}

/// Answers in order from a script; when it runs out, it acknowledges like the relay.
private final class ScriptedTransport: AIResponseReportTransport, @unchecked Sendable {
    enum Step { case status(Int), json(Int, [String: Any]), raw(Int, Data), failure }
    private let lock = NSLock()
    private var script: [Step] = []
    private var recorded: [URLRequest] = []
    var delay: UInt64 = 0

    func push(_ steps: Step...) { lock.lock(); script += steps; lock.unlock() }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    private func record(_ request: URLRequest) -> Step? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        return script.isEmpty ? nil : script.removeFirst()
    }

    func exchange(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let step = record(request)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        switch step {
        case .status(let status): return (status, Data())
        case .json(let status, let object): return (status, try JSONSerialization.data(withJSONObject: object))
        case .raw(let status, let data): return (status, data)
        case .failure: throw URLError(.timedOut)
        case nil:
            if request.httpMethod == "DELETE" {
                return (200, try JSONSerialization.data(withJSONObject: ["id": request.url!.lastPathComponent, "deleted": true]))
            }
            let id = (try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])["id"] as! String
            return (201, try JSONSerialization.data(withJSONObject: ["id": id, "accepted": true, "deletion_receipt": "receipt-" + id]))
        }
    }
}

private struct Env: @unchecked Sendable {
    let directory: URL
    let clock = Clock()
    let transport = ScriptedTransport()
    let queue: AIResponseReportQueue
    let delivery: AIResponseReportDelivery

    init(_ root: URL, _ name: String, endpoint: URL = AIResponseReportSender.relayEndpoint) {
        directory = root.appendingPathComponent(name, isDirectory: true)
        let clock = self.clock
        queue = AIResponseReportQueue(directory: directory, clock: { clock.now })
        delivery = AIResponseReportDelivery(queue: queue, sender: AIResponseReportSender(endpoint: endpoint, transport: transport),
                                            clock: { clock.now })
    }

    var files: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() }

    func stored(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(name))) as! [String: Any]
    }
}

private let replyA = AIResponseReference(conversationID: "C0FFEE00-0000-4000-8000-0000000000A1", messageKey: "11111111-0000-4000-8000-0000000000A1")
private let replyB = AIResponseReference(conversationID: "C0FFEE00-0000-4000-8000-0000000000A1", messageKey: "22222222-0000-4000-8000-0000000000B2")
private let day: Int64 = 24 * 60 * 60 * 1_000

/// The privacy policy says reports are not in iCloud or computer backups.
private func excludedFromBackup(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true
}

/// The relay's own intake rules (reports.ts at 964d7bec), applied to what was sent.
private func relayAccepts(_ request: URLRequest, now: Int64) -> Bool {
    guard let body = request.httpBody, body.count <= 16 * 1_024,
          let fields = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], fields.count == 5,
          let id = fields["id"] as? String, let reason = fields["reason"] as? String, let note = fields["note"] as? String,
          let response = fields["response"] as? String, let created = fields["created_at_ms"] as? NSNumber,
          !CFNumberIsFloatType(created), CFGetTypeID(created) != CFBooleanGetTypeID() else { return false }
    let uuid = try! NSRegularExpression(pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                                        options: [.caseInsensitive])
    return uuid.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
        && ["incorrect", "unsafe", "offensive", "privacy", "other"].contains(reason)
        && note.utf16.count <= 2_000 && !response.isEmpty && response.utf16.count <= 12_000
        && abs(now - created.int64Value) <= 7 * day
        && request.value(forHTTPHeaderField: "Origin") == nil
        && request.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first == "application/json"
}

@main enum CheckAIResponseReports {
    #if DEBUG
    static let config = "Debug"
    #else
    static let config = "Release"
    #endif

    static func main() async {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ai-reports-" + config, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let c = Checks()
        do {
            try await upload(root, c)
            try await retriesAndLimits(root, c)
            try await relayAnswers(root, c)
            try await intakeWindowAndManualReports(root, c)
            try await unreadableFilesFailClosed(root, c)
            try await deletion(root, c)
            try await oneDeliveryAtATime(root, c)
            try service(root, c)
            #if DEBUG
            try await fixtureTransport(root, c)
            #endif
            print("PASS AI response reports (\(config)): \(c.count) checks")
        } catch {
            print("FAIL: \(error) (\(config), after \(c.count) checks)")
            exit(1)
        }
    }

    /// The five fields, the limits Play applies before them, one header, and the files.
    static func upload(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "upload")
        let long = String(repeating: "a", count: 3_999) + "😀" + "tail"
        let saved = try e.queue.save(replyA, response: long, reason: "unsafe",
                                     note: " \n\t\u{1}" + String(repeating: "n", count: 1_200) + "  ")
        try c.expect(saved.response == String(repeating: "a", count: 3_999), "response keeps 4,000 UTF-16 units, never half a character")
        try c.expect(saved.note == String(repeating: "n", count: 1_000), "note trimmed like Kotlin and kept to 1,000 units")
        try c.expect(saved.id == saved.id.lowercased() && UUID(uuidString: saved.id) != nil, "the report ID is a lowercase UUID")
        try c.expect(saved.createdAtMs == e.clock.now && saved.status == .queuedLocal && saved.attempts == 0, "saved as pending, dated now")
        try c.expect(e.files == [saved.id + ".json"], "one file named by the report ID")
        let savedFile = e.directory.appendingPathComponent(saved.id + ".json")
        try c.expect(excludedFromBackup(e.directory) && excludedFromBackup(savedFile),
                     "the reports folder and file are excluded from iCloud and computer backups")
        let file = try e.stored(saved.id + ".json")
        try c.expect(Set(file.keys) == ["id", "conversationId", "messageKey", "response", "reason", "note", "createdAtMs", "status",
                                        "attempts", "nextAttemptAtMs", "acknowledgedAtMs", "deletionReceipt"],
                     "the stored record has Android's fields for an iOS reference")
        try c.expect(try e.queue.save(replyA, response: "other text", reason: "other", note: "") == saved,
                     "a second report of the same reply returns the saved one")
        for bad in [("incorrect", "text"), ("privacy", "text"), ("offensive", " \n ")] {
            do {
                _ = try e.queue.save(replyB, response: bad.1, reason: bad.0, note: "")
                throw Failure(description: "accepted reason \(bad.0) or a blank reply")
            } catch AIResponseReportError.invalid { try c.expect(true, "Play's three reasons and a non-blank reply only") }
        }

        try await e.delivery.deliverDue()
        let requests = e.transport.requests
        try c.expect(requests.count == 1, "one upload")
        let request = requests[0]
        try c.expect(request.httpMethod == "POST" && request.url == URL(string: "https://assistant-relay.woowtech.io/api/v1/ai-reports"),
                     "POST to the relay's report intake")
        try c.expect(request.allHTTPHeaderFields == ["Content-Type": "application/json; charset=utf-8"],
                     "no account, device, cookie or origin header; only the content type")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        try c.expect(Set(body.keys) == ["id", "reason", "note", "response", "created_at_ms"], "exactly the five fields")
        try c.expect(body["id"] as? String == saved.id && body["reason"] as? String == "unsafe" && body["note"] as? String == saved.note
                     && body["response"] as? String == saved.response && (body["created_at_ms"] as? NSNumber)?.int64Value == saved.createdAtMs,
                     "the fields carry the saved report")
        try c.expect(relayAccepts(request, now: e.clock.now), "the relay's intake rules accept it")
        let acknowledged = try e.queue.get(saved.id)
        try c.expect(acknowledged?.status == .acknowledged && acknowledged?.attempts == 1 && acknowledged?.acknowledgedAtMs == e.clock.now
                     && acknowledged?.deletionReceipt == "receipt-" + saved.id, "the acknowledgement and its deletion receipt are kept")
        try c.expect(excludedFromBackup(savedFile), "a rewritten report file stays out of backups")
        try await e.delivery.deliverDue()
        try c.expect(e.transport.requests.count == 1, "an acknowledged report is never sent again")

        // The largest Chinese reply and note still fit the relay's 16 KiB body.
        let wide = Env(root, "upload-wide")
        let report = try wide.queue.save(replyB, response: String(repeating: "檢", count: 5_000), reason: "offensive",
                                         note: String(repeating: "說", count: 1_500))
        try c.expect(report.response.utf16.count == 4_000 && report.note.utf16.count == 1_000, "Chinese text kept to Play's limits")
        try await wide.delivery.deliverDue()
        try c.expect(wide.transport.requests.count == 1 && relayAccepts(wide.transport.requests[0], now: wide.clock.now),
                     "4,000 Chinese characters and a 1,000-character note fit the relay")
    }

    /// 30 seconds, then 2 minutes, then no more automatic attempts; 重新傳送 starts over.
    static func retriesAndLimits(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "retries")
        let saved = try e.queue.save(replyA, response: "reply", reason: "offensive", note: "")
        e.transport.push(.status(503), .status(429), .failure)
        try await e.delivery.deliverDue()
        var report = try e.queue.get(saved.id)!
        try c.expect(report.status == .queuedLocal && report.attempts == 1 && report.nextAttemptAtMs == e.clock.now + 30_000,
                     "a busy relay is retried after 30 seconds")
        try await e.delivery.deliverDue()
        try c.expect(e.transport.requests.count == 1, "not before it is due")
        e.clock.advance(30_000)
        try await e.delivery.deliverDue()
        report = try e.queue.get(saved.id)!
        try c.expect(report.attempts == 2 && report.nextAttemptAtMs == e.clock.now + 120_000, "then after 2 minutes")
        e.clock.advance(120_000)
        try await e.delivery.deliverDue()
        report = try e.queue.get(saved.id)!
        try c.expect(e.transport.requests.count == 3 && report.attempts == 3 && report.status == .queuedLocal,
                     "a connection failure is retryable too")
        e.clock.advance(10 * 60_000)
        try await e.delivery.deliverDue()
        try c.expect(e.transport.requests.count == 3, "three automatic attempts at most")
        let retried = try await e.delivery.retry(saved.id)
        try c.expect(e.transport.requests.count == 4 && retried.status == .acknowledged && retried.attempts == 1,
                     "重新傳送 starts the count over and sends once")
        _ = try await e.delivery.retry(saved.id)
        try c.expect(e.transport.requests.count == 4, "retrying an acknowledged report sends nothing")
    }

    static func relayAnswers(_ root: URL, _ c: Checks) async throws {
        for status in [400, 403, 404, 413, 415, 302] {
            let e = Env(root, "rejected-\(status)")
            let saved = try e.queue.save(replyA, response: "reply", reason: "other", note: "")
            e.transport.push(.status(status))
            try await e.delivery.deliverDue()
            try c.expect(try e.queue.get(saved.id)?.status == .rejected, "HTTP \(status) is a rejection (redirects are not followed)")
            e.clock.advance(day)
            try await e.delivery.deliverDue()
            try c.expect(e.transport.requests.count == 1, "a rejected report is not sent again by itself")
        }
        let answers: [(String, (String) -> ScriptedTransport.Step)] = [
            ("an uppercase ID", { .json(201, ["id": $0.uppercased(), "accepted": true]) }),
            ("no accepted flag", { .json(201, ["id": $0]) }),
            ("accepted as a number", { .json(201, ["id": $0, "accepted": 1]) }),
            ("a body that is not JSON", { _ in .raw(201, Data("accepted".utf8)) }),
        ]
        for (label, answer) in answers {
            let e = Env(root, "unconfirmed-" + label.replacingOccurrences(of: " ", with: "-"))
            let saved = try e.queue.save(replyA, response: "reply", reason: "other", note: "")
            e.transport.push(answer(saved.id))
            try await e.delivery.deliverDue()
            let report = try e.queue.get(saved.id)!
            try c.expect(report.status == .queuedLocal && report.attempts == 1, "201 with \(label) is not an acknowledgement")
        }
        let padded = Env(root, "unconfirmed-large-body")
        let large = try padded.queue.save(replyA, response: "reply", reason: "other", note: "")
        padded.transport.push(.json(201, ["id": large.id, "accepted": true, "padding": String(repeating: "x", count: 20_000)]))
        try await padded.delivery.deliverDue()
        try c.expect(try padded.queue.get(large.id)?.status == .queuedLocal, "only the first 16 KiB of an answer is read")
        let repeated = Env(root, "acknowledged-without-receipt")
        let again = try repeated.queue.save(replyA, response: "reply", reason: "other", note: "")
        repeated.transport.push(.json(201, ["id": again.id, "accepted": true]))
        try await repeated.delivery.deliverDue()
        let report = try repeated.queue.get(again.id)!
        try c.expect(report.status == .acknowledged && report.deletionReceipt == nil, "a repeated ID is acknowledged without a receipt")

        let plain = Env(root, "plain-http", endpoint: URL(string: "http://example.com/api/v1/ai-reports")!)
        _ = try plain.queue.save(replyA, response: "reply", reason: "other", note: "")
        try await plain.delivery.deliverDue()
        try c.expect(plain.transport.requests.isEmpty, "never plain HTTP to another host")
        let local = Env(root, "local-http", endpoint: URL(string: "http://127.0.0.1:8787/api/v1/ai-reports")!)
        _ = try local.queue.save(replyA, response: "reply", reason: "other", note: "")
        try await local.delivery.deliverDue()
        try c.expect(local.transport.requests.count == 1, "plain HTTP only to this device, as on Android")
    }

    /// Older than seven days: never sent by itself; a new report replaces it only when asked.
    static func intakeWindowAndManualReports(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "manual")
        e.transport.push(.status(503))
        let old = try e.queue.save(replyA, response: "old reply", reason: "unsafe", note: "first")
        try await e.delivery.deliverDue()
        e.clock.advance(8 * day)
        try await e.delivery.deliverDue()
        try c.expect(e.transport.requests.count == 1, "a report dated outside the relay's seven days is not sent")
        _ = try await e.delivery.retry(old.id)
        try c.expect(e.transport.requests.count == 1, "nor by 重新傳送; 新建檢舉 is offered instead")
        let manual = try await e.delivery.createManual(replyA, response: old.response, reason: old.reason, note: old.note,
                                                       sourceID: old.id)
        try c.expect(manual.manualOnly && manual.replacementOf == old.id && manual.createdAtMs == e.clock.now && manual.id != old.id,
                     "the new report has a new ID and today's date")
        try c.expect(e.files.contains("manual-" + manual.id + ".json") && e.files.contains(old.id + ".json"), "the old report is kept")
        try c.expect(excludedFromBackup(e.directory.appendingPathComponent("manual-" + manual.id + ".json")),
                     "a new report's file is excluded from backups too")
        try await e.delivery.deliverDue()
        try c.expect(e.transport.requests.count == 1, "a new report is never sent automatically")
        let same = try await e.delivery.createManual(replyA, response: old.response, reason: old.reason, note: " first ",
                                                     sourceID: old.id)
        try c.expect(same == manual, "asking again with the same details returns it")
        do {
            _ = try await e.delivery.createManual(replyA, response: old.response, reason: "other", note: "changed", sourceID: old.id)
            throw Failure(description: "a changed replacement was created")
        } catch AIResponseReportError.existingManual(let existing) {
            try c.expect(existing == manual, "different details show the existing new report for review")
        }
        try c.expect(try e.queue.manualReports(conversationID: replyA.conversationID).map(\.id) == [manual.id],
                     "查看本機新建的檢舉 lists it")
        let sent = try await e.delivery.sendManual(manual.id)
        try c.expect(e.transport.requests.count == 2 && sent.status == .acknowledged, "送出 sends it once")
        let body = try JSONSerialization.jsonObject(with: e.transport.requests[1].httpBody!) as! [String: Any]
        try c.expect(body["id"] as? String == manual.id && relayAccepts(e.transport.requests[1], now: e.clock.now),
                     "with its own ID and date")
        let acknowledged = try await e.delivery.createManual(replyA, response: old.response, reason: old.reason, note: old.note,
                                                             sourceID: old.id)
        try c.expect(acknowledged.id == manual.id && acknowledged.status == .acknowledged, "a received replacement is not replaced")

        let blocked = Env(root, "blocked")
        let automatic = try blocked.queue.save(replyB, response: "reply", reason: "offensive", note: "")
        _ = try blocked.queue.createManual(replyB, response: "reply", reason: "offensive", note: "")
        try await blocked.delivery.deliverDue()
        try c.expect(blocked.transport.requests.isEmpty, "a new report pauses automatic sends of the same reply")
        try c.expect(try blocked.queue.find(replyB)?.id == automatic.id, "the automatic report is still the reply's report")
    }

    /// A file that cannot be read stops automatic sends; a damaged one stops only its reply.
    static func unreadableFilesFailClosed(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "unreadable")
        let first = try e.queue.save(replyA, response: "reply A", reason: "unsafe", note: "")
        try Data("{not json".utf8).write(to: e.directory.appendingPathComponent("broken.json"))
        for (label, attempt) in [("find", { _ = try e.queue.find(replyB) }), ("save", { _ = try e.queue.save(replyB, response: "b", reason: "other", note: "") }),
                                 ("list", { _ = try e.queue.manualReports(conversationID: replyA.conversationID) })] as [(String, () throws -> Void)] {
            do { try attempt(); throw Failure(description: label + " ignored an unreadable file") }
            catch AIResponseReportError.unidentified { try c.expect(true, label + " stops at an unreadable file") }
        }
        do { try await e.delivery.deliverDue(); throw Failure(description: "deliverDue ignored an unreadable file") }
        catch AIResponseReportError.unidentified { try c.expect(e.transport.requests.isEmpty, "no automatic send while a file is unreadable") }
        let second = try e.queue.save(replyB, response: "reply B", reason: "other", note: "", allowUnidentified: true)
        let sent = try await e.delivery.deliverOne(second.id)
        let chosen = e.transport.requests.map { (try? JSONSerialization.jsonObject(with: $0.httpBody ?? Data()) as? [String: Any])?["id"] as? String }
        try c.expect(sent.status == .acknowledged && chosen == [second.id], "了解風險並繼續 sends only the report the user chose")
        try c.expect(try e.queue.get(first.id, allowUnidentified: true)?.status == .queuedLocal, "the other report stays unsent")

        let d = Env(root, "damaged")
        let pending = try d.queue.save(replyB, response: "reply B", reason: "other", note: "")
        let damaged: [String: Any] = ["id": "33333333-0000-4000-8000-000000000003", "conversationId": replyA.conversationID,
                                      "messageKey": replyA.messageKey, "status": "unknown"]
        try JSONSerialization.data(withJSONObject: damaged).write(to: d.directory.appendingPathComponent("33333333-0000-4000-8000-000000000003.json"))
        do { _ = try d.queue.find(replyA); throw Failure(description: "a damaged report was ignored") }
        catch AIResponseReportError.damagedReference { try c.expect(true, "a damaged report of this reply cannot be overlooked") }
        try c.expect(try d.queue.find(replyB)?.id == pending.id, "other replies are unaffected")
        try await d.delivery.deliverDue()
        try c.expect(d.transport.requests.count == 1, "other replies' reports are still sent")
        let named: [String: Any] = ["id": "44444444-0000-4000-8000-000000000004", "conversationId": replyB.conversationID,
                                    "messageKey": replyB.messageKey, "response": "x", "reason": "other", "note": "",
                                    "createdAtMs": d.clock.now, "status": "queued_local", "attempts": 0, "nextAttemptAtMs": 0]
        try JSONSerialization.data(withJSONObject: named).write(to: d.directory.appendingPathComponent("misnamed.json"))
        do { _ = try d.queue.find(replyB); throw Failure(description: "a misnamed report was trusted") }
        catch AIResponseReportError.damagedReference { try c.expect(true, "a report under another file name counts as damaged") }
    }

    static func deletion(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "delete")
        let received = try e.queue.save(replyA, response: "reply", reason: "unsafe", note: "")
        try await e.delivery.deliverDue()
        let result = try await e.delivery.delete(received.id)
        let request = e.transport.requests[1]
        try c.expect(result == .deleted && request.httpMethod == "DELETE" && request.httpBody == nil
                     && request.url == AIResponseReportSender.relayEndpoint.appendingPathComponent(received.id)
                     && request.allHTTPHeaderFields == ["Authorization": "Bearer receipt-" + received.id],
                     "a received report is deleted on the relay with its receipt, and nothing else")
        try c.expect(e.files.isEmpty, "then from this device")

        for (status, expected, kept) in [(404, AIResponseReportDeletionResult.deleted, false), (401, .cannotVerify, true),
                                        (403, .cannotVerify, true), (500, .retryable, true)] {
            let s = Env(root, "delete-\(status)")
            let report = try s.queue.save(replyA, response: "reply", reason: "unsafe", note: "")
            try await s.delivery.deliverDue()
            s.transport.push(.status(status))
            let outcome = try await s.delivery.delete(report.id)
            let present = try s.queue.get(report.id) != nil
            try c.expect(outcome == expected && present == kept, "HTTP \(status) on deletion: \(expected), kept \(kept)")
        }
        let notDeleted = Env(root, "delete-unconfirmed")
        let report = try notDeleted.queue.save(replyA, response: "reply", reason: "unsafe", note: "")
        try await notDeleted.delivery.deliverDue()
        notDeleted.transport.push(.json(200, ["id": report.id, "deleted": false]))
        let unconfirmed = try await notDeleted.delivery.delete(report.id)
        let stillThere = try notDeleted.queue.get(report.id) != nil
        try c.expect(unconfirmed == .retryable && stillThere, "an answer that does not confirm deletion keeps the report")

        let noReceipt = Env(root, "delete-no-receipt")
        let repeated = try noReceipt.queue.save(replyA, response: "reply", reason: "unsafe", note: "")
        noReceipt.transport.push(.json(201, ["id": repeated.id, "accepted": true]))
        try await noReceipt.delivery.deliverDue()
        let withoutReceipt = try await noReceipt.delivery.delete(repeated.id)
        try c.expect(withoutReceipt == .cannotVerify && noReceipt.transport.requests.count == 1 && noReceipt.files.count == 1,
                     "without a receipt nothing is asked of the relay and the report is kept")

        let local = Env(root, "delete-local")
        let unsent = try local.queue.save(replyA, response: "reply", reason: "unsafe", note: "")
        let localOnly = try await local.delivery.delete(unsent.id)
        try c.expect(localOnly == .deleted && local.transport.requests.isEmpty && local.files.isEmpty,
                     "a report never sent is removed from this device only")
        let tried = try local.queue.save(replyB, response: "reply", reason: "unsafe", note: "")
        local.transport.push(.failure)
        try await local.delivery.deliverDue()
        let unknown = try await local.delivery.delete(tried.id)
        let kept = try local.queue.get(tried.id) != nil
        try c.expect(unknown == .cannotVerify && kept, "a report that may have arrived without an answer is kept")
        let manual = try local.queue.createManual(replyA, response: "reply", reason: "other", note: "")
        _ = try await local.delivery.sendManual(manual.id)
        let manualDeleted = try await local.delivery.delete(manual.id)
        try c.expect(manualDeleted == .deleted && !local.files.contains("manual-" + manual.id + ".json"),
                     "a new report is deleted the same way")
    }

    /// Android holds one lock across each send: concurrent rounds never send a report twice.
    static func oneDeliveryAtATime(_ root: URL, _ c: Checks) async throws {
        let e = Env(root, "concurrent")
        for index in 0..<3 {
            _ = try e.queue.save(AIResponseReference(conversationID: replyA.conversationID, messageKey: "key-\(index)"),
                                 response: "reply \(index)", reason: "other", note: "")
        }
        e.transport.delay = 50_000_000
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask { try? await e.delivery.deliverDue() } }
        }
        try c.expect(e.transport.requests.count == 3, "each report is sent once")
    }

    static func service(_ root: URL, _ c: Checks) throws {
        let support = root.appendingPathComponent("support", isDirectory: true)
        let personal = AIResponseReportService.make(arguments: [], supportDirectory: support)
        try c.expect(personal.queue.directory == support.appendingPathComponent("AIResponseReports/personal", isDirectory: true),
                     "reports live in Application Support/AIResponseReports/personal")
        try c.expect(personal.sender.endpoint == AIResponseReportSender.relayEndpoint && personal.sender.transport is AIResponseReportURLSessionTransport,
                     "the App sends to the relay")
        let namespace = UUID()
        let test = AIResponseReportService.make(arguments: ["-UITestMode", "-UITestNamespace", namespace.uuidString], supportDirectory: support)
        #if DEBUG
        try c.expect(test.queue.directory.lastPathComponent == "test-" + namespace.uuidString
                     && test.sender.transport is AIResponseReportFixtureTransport, "UI tests use their namespace and never the relay")
        try c.expect(AIResponseReportService.testScope(["-LiveModelUITest"]) == "test-unscoped"
                     && AIResponseReportService.testScope(["-UITestMode", "-UITestNamespace", "not-a-uuid"]) == "test-unscoped",
                     "a test without a namespace still stays off the relay")
        #else
        try c.expect(test.queue.directory.lastPathComponent == "personal" && test.sender.transport is AIResponseReportURLSessionTransport,
                     "Release builds ignore UI test switches")
        #endif
    }

    #if DEBUG
    static func fixtureTransport(_ root: URL, _ c: Checks) async throws {
        let support = root.appendingPathComponent("fixture", isDirectory: true)
        let arguments = ["-UITestMode", "-UITestNamespace", UUID().uuidString]
        let delivery = AIResponseReportService.make(arguments: arguments, supportDirectory: support)
        let report = try await delivery.save(replyA, response: "reply", reason: "offensive", note: "", allowUnidentified: false)
        try await delivery.deliverDue()
        let sent = try delivery.queue.get(report.id)
        try c.expect(sent?.status == .acknowledged && sent?.deletionReceipt == "fixture-deletion-receipt", "the UI test relay acknowledges")
        let removed = try await delivery.delete(report.id)
        try c.expect(removed == .deleted, "and deletes")
        _ = try await delivery.save(replyB, response: "reply", reason: "offensive", note: "", allowUnidentified: false)
        let reset = AIResponseReportService.make(arguments: arguments + ["-UITestResetStorage"], supportDirectory: support)
        try c.expect(try reset.queue.all().isEmpty, "-UITestResetStorage starts the namespace empty")
    }
    #endif
}
