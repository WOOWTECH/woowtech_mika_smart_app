import Foundation
#if !MODEL_HTTP_FAILURE_HARNESS
@testable import AssistantModels
#endif

/// OFFLINE ONLY: every URLSession request is intercepted, including unknown hosts.
/// Synthetic strings are intentional leakage sentinels, never real credentials or service data.
enum ModelHTTPFailureDiagnosticChecks {
    struct Failure: Error { let name: String }
    private static func expect(_ value: @autoclosure () -> Bool, _ name: String) throws {
        guard value() else { throw Failure(name: name) }
    }
    private static let marker = "OFFLINE_SECRET_SENTINEL"
    private static let input = [ModelMessage(role: "user", content: marker)]

    static func classification() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func diagnostic(_ retry: String? = nil, status: Int = 429) -> ModelHTTPFailureDiagnostic {
            let response = HTTPURLResponse(url: URL(string: "https://offline.invalid/" + marker)!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: retry.map { ["Retry-After": $0] })!
            return ModelHTTPFailureDiagnostic(response: response, now: now)!
        }
        let headers = diagnostic("30")
        try expect(headers.category == .rateLimitOrQuota && headers.status == 429, "bare 429 remains ambiguous")
        try expect(headers.retryAfterKind == .delaySeconds && headers.retryAfterSeconds == 30, "numeric Retry-After")
        let bodies: [(String, ModelHTTPFailureDiagnostic.Category)] = [
            (#"{"error":{"code":"insufficient_quota","message":"OFFLINE_SECRET_SENTINEL"}}"#, .quotaExhausted),
            (#"{"error":{"type":"insufficient_quota"}}"#, .quotaExhausted),
            (#"{"error":{"code":"rate_limit_exceeded"}}"#, .rateLimited),
            (#"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#, .planLimitReached),
            (#"{"error":{"message":"insufficient_quota rate_limit_exceeded"}}"#, .rateLimitOrQuota),
            (#"{"error":{"code":"OFFLINE_SECRET_SENTINEL","type":"insufficient_quota"}}"#, .rateLimitOrQuota),
            (#"{"error":{"code":"insufficient_quota","code":"rate_limit_exceeded"}}"#, .rateLimitOrQuota),
            (#"{"error":{"code":"insufficient_quota"},"error":{"code":"rate_limit_exceeded"}}"#, .rateLimitOrQuota),
            (#"{"error":{"code":"INSUFFICIENT_QUOTA"}}"#, .rateLimitOrQuota),
            (#"{"error":{"code":"insufficient_quota"}"#, .rateLimitOrQuota),
            ("<html>insufficient_quota</html>", .rateLimitOrQuota),
        ]
        for (body, category) in bodies {
            let event = headers.classifying(Data(body.utf8))
            try expect(event.category == category, "only exact unambiguous codes classify")
            try expect(event.id == headers.id && event.status == 429, "attempt and real status retained")
            try expect(event.phase == .bodyComplete && event.retryAfterSeconds == 30, "body metadata retained")
            try expect(!event.message.contains(marker) && !event.message.contains("https"), "body and endpoint excluded")
        }
        let oversized = Data((String(repeating: " ", count: 16_384) + bodies[0].0).utf8)
        try expect(headers.classifying(oversized).category == .rateLimitOrQuota, "oversized body not classified")
        try expect(headers.classifying(nil).phase == .bodyUnavailable, "unavailable body explicit")
        try expect(diagnostic().retryAfterKind == .absent, "absent header explicit")
        for invalid in ["", "-1", "+1", "1.5", "1e2", marker, "31536001", String(repeating: "9", count: 80)] {
            let event = diagnostic(invalid)
            try expect(event.retryAfterKind == .invalid && event.retryAfterSeconds == nil, "unsafe Retry-After rejected")
            try expect(!event.message.contains(marker), "unsafe header excluded")
        }
        try expect(diagnostic(" \t0 ").retryAfterSeconds == 0, "zero and optional whitespace")
        let date = diagnostic("Tue, 14 Nov 2023 22:14:20 GMT")
        try expect(date.retryAfterKind == .httpDate && date.retryAfterSeconds == 60, "HTTP date normalized")
        try expect(diagnostic("Tue, 14 Nov 2023 22:12:20 GMT").retryAfterSeconds == 0, "past date normalized")
        try expect(diagnostic("Wed, 14 Nov 2023 22:14:20 GMT").retryAfterKind == .invalid, "wrong weekday rejected")
        try expect(diagnostic(status: 402).category == .paymentRequired, "402 is status evidence only")
        try expect(diagnostic(status: 401).category == .authentication, "401 category retained")
        try expect(diagnostic(status: 503).category == .server, "503 category retained")
    }

    static func transport() async throws {
        for streamed in [false, true] {
            for (body, expected) in [
                (#"{"error":{"code":"insufficient_quota","message":"OFFLINE_SECRET_SENTINEL"}}"#, ModelHTTPFailureDiagnostic.Category.quotaExhausted),
                (#"{"error":{"code":"rate_limit_exceeded"}}"#, .rateLimited),
                (#"{"error":{"message":"insufficient_quota"}}"#, .rateLimitOrQuota),
            ] {
                let fixture = OfflineModelFailureProtocol.Fixture(body: Data(body.utf8))
                let (session, config) = fixture.sessionAndConfiguration()
                defer { session.invalidateAndCancel(); fixture.remove() }
                let records = OfflineModelFailureRecords()
                let client = HTTPChatModelClient(session: session, timeoutNanoseconds: 2_000_000_000,
                                                observeHTTPFailure: { records.add($0) })
                let error = await failure(client, config: config, streamed: streamed)
                try expect(error as? HTTPChatModelError == .httpStatus(429), "chat error semantics unchanged")
                try expect(fixture.requests == 1, "chat rejection never resends")
                try expect(records.values.count == 2, "headers and body receipts")
                try expect(records.values.last?.category == expected, "transport code classification")
                try expect(records.values.first?.id == records.values.last?.id, "receipts correlated per attempt")
                try expect(records.values.allSatisfy { $0.status == 429 && $0.retryAfterSeconds == 7 }, "wire status and Retry-After")
                try expect(records.values.allSatisfy { !$0.message.contains(marker) }, "transport redaction")
            }
        }
        for streamed in [false, true] {
            let fixture = OfflineModelFailureProtocol.Fixture(holdAfterHeaders: true)
            let (session, config) = fixture.sessionAndConfiguration()
            defer { session.invalidateAndCancel(); fixture.remove() }
            let records = OfflineModelFailureRecords()
            let client = HTTPChatModelClient(session: session, timeoutNanoseconds: 2_000_000_000,
                                            observeHTTPFailure: { records.add($0) })
            let start = ContinuousClock.now
            let error = await failure(client, config: config, streamed: streamed)
            try expect(error as? HTTPChatModelError == .httpStatus(429), "stalled body retains original status")
            try expect(start.duration(to: .now) < .seconds(2), "diagnostics bounded before total request deadline")
            try expect(records.values.last?.phase == .bodyUnavailable && fixture.requests == 1, "stalled body has no retry")
        }
        let large = OfflineModelFailureProtocol.Fixture(body: Data(repeating: 65, count: 16_385))
        let (largeSession, largeConfig) = large.sessionAndConfiguration()
        defer { largeSession.invalidateAndCancel(); large.remove() }
        let largeRecords = OfflineModelFailureRecords()
        let largeClient = HTTPChatModelClient(session: largeSession, timeoutNanoseconds: 2_000_000_000,
                                             observeHTTPFailure: { largeRecords.add($0) })
        let largeError = await failure(largeClient, config: largeConfig, streamed: false)
        try expect(largeError as? HTTPChatModelError == .httpStatus(429), "oversize status retained")
        try expect(largeRecords.values.last?.phase == .bodyUnavailable, "partial body never classified")

        for code in [URLError.Code.cannotConnectToHost, .timedOut, .cancelled] {
            let fixture = OfflineModelFailureProtocol.Fixture(failure: URLError(code, userInfo: [NSLocalizedDescriptionKey: marker]))
            let (session, config) = fixture.sessionAndConfiguration()
            defer { session.invalidateAndCancel(); fixture.remove() }
            let records = OfflineModelFailureRecords()
            let client = HTTPChatModelClient(session: session, timeoutNanoseconds: 2_000_000_000,
                                            observeHTTPFailure: { records.add($0) })
            let error = await failure(client, config: config, streamed: false)
            if code == .cancelled { try expect(error is CancellationError, "cancelled transport stays cancellation") }
            else { try expect(error as? HTTPChatModelError == (code == .timedOut ? .timedOut : .transportFailure), "sanitized transport error") }
            try expect(records.values.isEmpty && fixture.requests == 1, "no invented HTTP evidence for transport failures")
            try expect(!String(describing: error).contains(marker), "arbitrary transport detail sanitized")
        }
        let held = OfflineModelFailureProtocol.Fixture(holdAfterHeaders: true)
        let (session, config) = held.sessionAndConfiguration()
        defer { session.invalidateAndCancel(); held.remove() }
        let records = OfflineModelFailureRecords()
        let client = HTTPChatModelClient(session: session, timeoutNanoseconds: 2_000_000_000,
                                        observeHTTPFailure: { records.add($0) })
        let task = Task { await failure(client, config: config, streamed: false) }
        for _ in 0..<100 {
            if !records.values.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        task.cancel()
        let cancelled = await task.value
        try expect(cancelled is CancellationError, "cancellation during diagnostic body collection preserved")
        try expect(held.requests == 1, "cancellation never resends")
    }

    static func accountSemantics() async throws {
        for kind in [ModelAccountKind.chatGPT, .xai] {
            for streamed in [false, true] {
                for (body, quota) in [(#"{"error":{"code":"insufficient_quota"}}"#, true), ("{}", false)] {
                    let fixture = OfflineModelFailureProtocol.Fixture(body: Data(body.utf8))
                    let (session, plain) = fixture.sessionAndConfiguration()
                    defer { session.invalidateAndCancel(); fixture.remove() }
                    let config = ModelConfiguration(baseURL: plain.baseURL, model: marker,
                        account: ModelAccountRoute(kind: kind, providerID: UUID()))
                    let tokens = OfflineModelFailureTokens()
                    let records = OfflineModelFailureRecords()
                    let client = ResponsesModelClient(session: session, timeoutNanoseconds: 2_000_000_000, accounts: tokens,
                                                      observeHTTPFailure: { records.add($0) })
                    let error = await failure(client, config: config, streamed: streamed)
                    if quota { try expect(error as? HTTPChatModelError == .httpStatus(402), "account quota mapping preserved") }
                    else if kind == .chatGPT { try expect(error as? ModelAccountError == .planLimitReached, "plan limit semantics preserved") }
                    else { try expect(error as? HTTPChatModelError == .httpStatus(429), "xAI rate semantics preserved") }
                    try expect(records.values.count == 2 && records.values.allSatisfy { $0.status == 429 }, "account mapping does not overwrite raw 429")
                    try expect(records.values.last?.category == (quota ? .quotaExhausted : .rateLimitOrQuota), "account evidence only")
                    try expect(fixture.requests == 1 && tokens.count == 1, "no quota retry or credential refresh")
                }
            }
        }
        // Existing reference-bound 401: refresh for next explicit request, never resend this one.
        let fixture = OfflineModelFailureProtocol.Fixture(status: 401)
        let (session, plain) = fixture.sessionAndConfiguration()
        defer { session.invalidateAndCancel(); fixture.remove() }
        let config = ModelConfiguration(baseURL: plain.baseURL, model: marker,
            account: ModelAccountRoute(kind: .chatGPT, providerID: UUID()))
        let tokens = OfflineModelFailureTokens()
        let records = OfflineModelFailureRecords()
        let client = ResponsesModelClient(session: session, timeoutNanoseconds: 2_000_000_000, accounts: tokens,
                                          observeHTTPFailure: { records.add($0) })
        do {
            _ = try await client.complete(messages: input, configuration: config, apiKey: marker, onDispatch: {})
            throw Failure(name: "expected account authentication rejection")
        } catch let error as ModelAccountError {
            try expect(error == .unauthorized(.chatGPT), "auth semantic unchanged")
        }
        try expect(fixture.requests == 1 && tokens.count == 2, "reference-bound auth refresh has no resend")
        try expect(records.values.count == 1 && records.values.first?.status == 401, "auth header recorded once")
    }

    private static func failure(_ client: any StreamingChatModelClient, config: ModelConfiguration, streamed: Bool) async -> Error {
        do {
            if streamed {
                for try await _ in client.stream(messages: input, configuration: config, apiKey: marker) {}
            } else { _ = try await client.complete(messages: input, configuration: config, apiKey: marker) }
            return Failure(name: "expected failure")
        } catch { return error }
    }
}

private final class OfflineModelFailureRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ModelHTTPFailureDiagnostic] = []
    func add(_ value: ModelHTTPFailureDiagnostic) { lock.lock(); defer { lock.unlock() }; stored.append(value) }
    var values: [ModelHTTPFailureDiagnostic] { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class OfflineModelFailureTokens: ModelAccountTokenProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func accessToken(for route: ModelAccountRoute, rejected: String?) async throws -> String { next() }
    private func next() -> String { lock.lock(); defer { lock.unlock() }; calls += 1; return "OFFLINE_TOKEN" }
}

private final class OfflineModelFailureProtocol: URLProtocol {
    final class Fixture: @unchecked Sendable {
        let id = UUID().uuidString.lowercased()
        let status: Int
        let body: Data
        let holdAfterHeaders: Bool
        let failure: URLError?
        private let lock = NSLock()
        private var count = 0
        var requests: Int { lock.lock(); defer { lock.unlock() }; return count }
        func seen() { lock.lock(); defer { lock.unlock() }; count += 1 }
        init(status: Int = 429, body: Data = Data(), holdAfterHeaders: Bool = false, failure: URLError? = nil) {
            self.status = status; self.body = body; self.holdAfterHeaders = holdAfterHeaders; self.failure = failure
        }
        func sessionAndConfiguration() -> (URLSession, ModelConfiguration) {
            OfflineModelFailureProtocol.registry.lock.lock(); OfflineModelFailureProtocol.registry.fixtures[id + ".invalid"] = self; OfflineModelFailureProtocol.registry.lock.unlock()
            let session = URLSessionConfiguration.ephemeral
            session.protocolClasses = [OfflineModelFailureProtocol.self]
            session.urlCache = nil; session.httpCookieStorage = nil; session.urlCredentialStorage = nil
            return (URLSession(configuration: session), ModelConfiguration(baseURL: URL(string: "https://\(id).invalid/v1")!, model: "OFFLINE_SECRET_SENTINEL"))
        }
        func remove() { OfflineModelFailureProtocol.registry.lock.lock(); defer { OfflineModelFailureProtocol.registry.lock.unlock() }; OfflineModelFailureProtocol.registry.fixtures.removeValue(forKey: id + ".invalid") }
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var fixtures: [String: Fixture] = [:]
    }
    private static let registry = Registry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.registry.lock.lock()
        let fixture = Self.registry.fixtures[request.url?.host ?? ""]
        Self.registry.lock.unlock()
        guard let fixture, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        fixture.seen()
        if let failure = fixture.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json", "Retry-After": "7"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if fixture.holdAfterHeaders { return }
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

#if MODEL_HTTP_FAILURE_HARNESS
@main enum ModelHTTPFailureHarness {
    static func main() async {
        do {
            try ModelHTTPFailureDiagnosticChecks.classification()
            print("OFFLINE PASS: closed classification, redaction, Retry-After")
            try await ModelHTTPFailureDiagnosticChecks.transport()
            print("OFFLINE PASS: synthetic chat transport, body bounds, cancellation, no retries")
            try await ModelHTTPFailureDiagnosticChecks.accountSemantics()
            print("OFFLINE PASS: synthetic account mappings and reference-bound authentication")
            print("OFFLINE ONLY: no real-service or commercial real-device acceptance")
        } catch let error as ModelHTTPFailureDiagnosticChecks.Failure {
            print("OFFLINE FAIL: \(error.name)"); exit(1)
        } catch { print("OFFLINE FAIL: unexpected sanitized test error"); exit(1) }
    }
}
#endif
