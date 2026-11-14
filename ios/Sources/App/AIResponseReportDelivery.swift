import Foundation

enum AIResponseReportDeliveryResult: Equatable, Sendable {
    case acknowledged(deletionReceipt: String?)
    case retryable
    case rejected
}

enum AIResponseReportDeletionResult: Equatable, Sendable {
    case deleted, retryable, cannotVerify
}

/// One HTTP exchange; the App sends through URLSession, checks through a fake.
protocol AIResponseReportTransport: Sendable {
    func exchange(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

/// The relay's public report intake (Android AiResponseReportSender): no
/// account, pairing, device token or cookie, and exactly the five fields the
/// relay accepts. Redirects are never followed.
struct AIResponseReportSender: Sendable {
    static let relayEndpoint = URL(string: "https://assistant-relay.woowtech.io/api/v1/ai-reports")!

    let endpoint: URL
    let transport: any AIResponseReportTransport

    func send(_ report: AIResponseReport) async -> AIResponseReportDeliveryResult {
        guard Self.allowed(endpoint) else { return .retryable }
        let fields: [String: Any] = ["id": report.id, "reason": report.reason, "note": report.note,
                                     "response": report.response, "created_at_ms": report.createdAtMs]
        guard let body = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return .retryable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (status, data) = try? await transport.exchange(request) else { return .retryable }
        switch status {
        case 201:
            guard let object = Self.object(data), object["id"] as? String == report.id, Self.flag(object["accepted"]) == true else {
                return .retryable
            }
            return .acknowledged(deletionReceipt: object["deletion_receipt"] as? String)
        case 408, 429, 500...599: return .retryable
        default: return .rejected
        }
    }

    func delete(_ report: AIResponseReport) async -> AIResponseReportDeletionResult {
        guard let token = report.deletionReceipt, !AIResponseReportQueue.isBlank(token) else { return .cannotVerify }
        guard Self.allowed(endpoint) else { return .retryable }
        var request = URLRequest(url: endpoint.appendingPathComponent(report.id, isDirectory: false))
        request.httpMethod = "DELETE"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (status, data) = try? await transport.exchange(request) else { return .retryable }
        switch status {
        case 200:
            guard let object = Self.object(data), object["id"] as? String == report.id, Self.flag(object["deleted"]) == true else {
                return .retryable
            }
            return .deleted
        // Expired or already removed on the server; the device copy can go too.
        case 404: return .deleted
        case 401, 403: return .cannotVerify
        default: return .retryable
        }
    }

    /// HTTPS, or plain HTTP to this device only.
    private static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? ""))
    }

    /// Android reads at most the first 16 KiB of a reply.
    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data.prefix(16_384))) as? [String: Any]
    }

    private static func flag(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}

/// URLSession without cookies, cache or redirects, 15 seconds a call like Android's client.
struct AIResponseReportURLSessionTransport: AIResponseReportTransport {
    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func exchange(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let (data, response) = try await Self.session.data(for: request, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (http.statusCode, data)
    }
}

/// Android's AiResponseReportDelivery: every operation holds one lock across
/// its network call, so two deliveries never send or delete the same report.
final class AIResponseReportDelivery: @unchecked Sendable {
    static let maximumAttempts = 3

    let queue: AIResponseReportQueue
    let sender: AIResponseReportSender
    private let clock: @Sendable () -> Int64
    private let gate = Gate()

    init(queue: AIResponseReportQueue, sender: AIResponseReportSender,
         clock: @escaping @Sendable () -> Int64 = AIResponseReportQueue.currentTimeMs) {
        self.queue = queue; self.sender = sender; self.clock = clock
    }

    /// An actor alone would let a second operation in while the first waits for the network.
    private actor Gate {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func acquire() async {
            guard busy else { busy = true; return }
            await withCheckedContinuation { waiting.append($0) }
        }
        func release() {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
    }

    private func exclusive<T>(_ body: () async throws -> T) async throws -> T {
        await gate.acquire()
        do {
            let value = try await body()
            await gate.release()
            return value
        } catch {
            await gate.release()
            throw error
        }
    }

    func delete(_ id: String, allowUnidentified: Bool = false) async throws -> AIResponseReportDeletionResult {
        try await exclusive {
            guard let report = try queue.get(id, allowUnidentified: allowUnidentified) else { return .deleted }
            let result: AIResponseReportDeletionResult
            if report.status == .acknowledged { result = await sender.delete(report) }
            else if report.attempts == 0 { result = .deleted }
            // A lost acknowledgement could have left a copy on the server.
            else { result = .cannotVerify }
            if result == .deleted {
                let removed = try queue.remove(id, allowUnidentified: allowUnidentified)
                if !removed { return .retryable }
            }
            return result
        }
    }

    /// Sends the automatic reports that are due, at most three times each. Any
    /// unreadable or damaged file stops this round, as on Android.
    func deliverDue() async throws {
        try await exclusive {
            let due = try queue.all().filter { isDue($0) }
            for report in due {
                guard let current = try queue.get(report.id) else { continue }
                let blocked = try queue.autoBlockedByManual(current)
                guard !blocked else { continue }
                let selected = try queue.find(current.reference)
                guard selected?.id == current.id, isDue(current) else { continue }
                _ = try queue.recordAttempt(current.id, result: await sender.send(current), now: clock())
            }
        }
    }

    private func isDue(_ report: AIResponseReport) -> Bool {
        let now = clock()
        return !report.manualOnly && !report.outsideIntakeWindow(now: now) && report.status == .queuedLocal
            && report.attempts < Self.maximumAttempts && report.nextAttemptAtMs <= now
    }

    func retry(_ id: String, allowUnidentified: Bool = false) async throws -> AIResponseReport {
        try await exclusive {
            guard let current = try queue.get(id, allowUnidentified: allowUnidentified), !current.manualOnly,
                  let selected = try queue.find(current.reference, allowUnidentified: allowUnidentified) else {
                throw AIResponseReportError.invalid
            }
            if selected.status == .acknowledged || selected.outsideIntakeWindow(now: clock()) { return selected }
            let report = try queue.retry(selected.id, allowUnidentified: allowUnidentified)
            return try queue.recordAttempt(report.id, result: await sender.send(report), now: clock(),
                                           allowUnidentified: allowUnidentified)
        }
    }

    /// The user accepted the risk for this report only; other queued reports stay unsent.
    func deliverOne(_ id: String) async throws -> AIResponseReport {
        try await exclusive {
            guard let current = try queue.get(id, allowUnidentified: true), !current.manualOnly,
                  let selected = try queue.find(current.reference, allowUnidentified: true) else {
                throw AIResponseReportError.invalid
            }
            let now = clock()
            let blocked = try queue.autoBlockedByManual(selected, allowUnidentified: true)
            if selected.status != .queuedLocal || blocked || selected.outsideIntakeWindow(now: now)
                || selected.attempts >= Self.maximumAttempts || selected.nextAttemptAtMs > now { return selected }
            return try queue.recordAttempt(selected.id, result: await sender.send(selected), now: clock(), allowUnidentified: true)
        }
    }

    /// A new report in place of an old one the relay never confirmed in time.
    /// The old one is checked again first and a known receipt is never replaced.
    func createManual(_ reference: AIResponseReference, response: String, reason: String, note: String,
                      sourceID: String?, allowUnidentified: Bool = false) async throws -> AIResponseReport {
        try await exclusive {
            if let sourceID {
                guard let source = try queue.getManual(sourceID, allowUnidentified: allowUnidentified)
                        ?? queue.get(sourceID, allowUnidentified: allowUnidentified) else { throw AIResponseReportError.invalid }
                let found: AIResponseReport?
                if source.manualOnly { found = source }
                else { found = try queue.find(source.reference, allowUnidentified: allowUnidentified) }
                guard let selected = found else { throw AIResponseReportError.invalid }
                if selected.status == .acknowledged { return selected }
                guard selected.id == source.id, source.outsideIntakeWindow(now: clock()),
                      reference == source.reference, response == source.response else { throw AIResponseReportError.invalid }
                let replacements = try queue.manualReports(conversationID: reference.conversationID, allowUnidentified: allowUnidentified)
                    .filter { $0.replacementOf == sourceID }
                if let acknowledged = replacements.first(where: { $0.status == .acknowledged }) { return acknowledged }
                if let current = replacements.first(where: { !$0.outsideIntakeWindow(now: clock()) }) {
                    if current.response != response || current.reason != reason
                        || current.note != AIResponseReportQueue.normalizedNote(note) {
                        throw AIResponseReportError.existingManual(current)
                    }
                    return current
                }
            }
            return try queue.createManual(reference, response: response, reason: reason, note: note, replacementOf: sourceID)
        }
    }

    func sendManual(_ id: String, allowUnidentified: Bool = false) async throws -> AIResponseReport {
        try await exclusive {
            guard let report = try queue.getManual(id, allowUnidentified: allowUnidentified) else { throw AIResponseReportError.invalid }
            if report.status == .acknowledged || report.outsideIntakeWindow(now: clock()) { return report }
            return try queue.recordManualAttempt(id, result: await sender.send(report), now: clock(),
                                                 allowUnidentified: allowUnidentified)
        }
    }

    // MARK: Reads for the report sheet, off the main thread like Android's Dispatchers.IO

    func find(_ reference: AIResponseReference, allowUnidentified: Bool) async throws -> AIResponseReport? {
        try queue.find(reference, allowUnidentified: allowUnidentified)
    }

    func save(_ reference: AIResponseReference, response: String, reason: String, note: String,
              allowUnidentified: Bool) async throws -> AIResponseReport {
        try queue.save(reference, response: response, reason: reason, note: note, allowUnidentified: allowUnidentified)
    }

    func report(_ id: String, manual: Bool, allowUnidentified: Bool) async throws -> AIResponseReport? {
        try manual ? queue.getManual(id, allowUnidentified: allowUnidentified) : queue.get(id, allowUnidentified: allowUnidentified)
    }

    func manualReports(conversationID: String, allowUnidentified: Bool) async throws -> [AIResponseReport] {
        try queue.manualReports(conversationID: conversationID, allowUnidentified: allowUnidentified)
    }

    /// While the chat is on screen, due reports are sent every 30 seconds (Android ChatScreen).
    func deliverDueWhileVisible() async {
        while !Task.isCancelled {
            try? await deliverDue()
            try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
    }
}
