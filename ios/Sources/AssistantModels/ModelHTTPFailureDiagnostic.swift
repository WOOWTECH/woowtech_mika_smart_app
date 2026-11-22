import Foundation
#if canImport(os)
import os
#endif

/// Diagnostic evidence only; never changes the error thrown, credentials, or retry policy.
/// No request/response objects, provider strings, or raw headers are retained.
struct ModelHTTPFailureDiagnostic: Equatable, Sendable {
    enum Category: String, Sendable {
        case authentication, paymentRequired, notFound, server, rejected, redirect
        // HTTP 429 alone cannot establish quota exhaustion versus throttling.
        case rateLimitOrQuota, quotaExhausted, rateLimited, planLimitReached
    }
    enum Phase: String, Sendable { case headers, bodyComplete, bodyUnavailable }
    enum RetryAfterKind: String, Sendable { case absent, delaySeconds, httpDate, invalid }

    static let maximumBodyBytes = 16 * 1024
    let id: UUID // Fresh per HTTP attempt, unrelated to any user/conversation/provider ID.
    let status: Int
    let category: Category
    let phase: Phase
    let retryAfterKind: RetryAfterKind
    let retryAfterSeconds: Int?

    init?(response: HTTPURLResponse, now: Date = Date()) {
        let status = response.statusCode
        guard (300...599).contains(status) else { return nil }
        id = UUID()
        self.status = status
        phase = .headers
        switch status {
        case 300..<400: category = .redirect
        case 401, 403: category = .authentication
        case 402: category = .paymentRequired
        case 404: category = .notFound
        case 429: category = .rateLimitOrQuota
        case 500...599: category = .server
        default: category = .rejected
        }
        let retry = Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: now)
        retryAfterKind = retry.0
        retryAfterSeconds = retry.1
    }

    private init(_ headers: Self, body: Data?) {
        id = headers.id
        status = headers.status // Actual HTTP status, never a synthesized provider-error status.
        phase = body == nil ? .bodyUnavailable : .bodyComplete
        category = body.flatMap(Self.bodyCategory) ?? headers.category
        retryAfterKind = headers.retryAfterKind
        retryAfterSeconds = headers.retryAfterSeconds
    }

    func classifying(_ body: Data?) -> Self { Self(self, body: body) }

    /// Closed fields only. Never interpolate Error, URLResponse, headers, or a provider code.
    var message: String {
        "model_http_failure id=\(id.uuidString.lowercased()) phase=\(phase.rawValue)"
            + " category=\(category.rawValue) status=\(status)"
            + " retry_after=\(retryAfterKind.rawValue) retry_after_seconds=\(retryAfterSeconds.map(String.init) ?? "none")"
    }

    func log() {
        #if canImport(os)
        let logger = Logger(subsystem: "io.woowtech.assistant", category: "model-diagnostic")
        logger.notice("\(message, privacy: .public)")
        #endif
    }

    /// Only exact, structured error.code/error.type values may refine the status category.
    /// Unknown codes, free text, malformed/duplicate JSON keys and partial bodies do not.
    private static func bodyCategory(_ body: Data) -> Category? {
        guard body.count <= maximumBodyBytes,
              let text = String(data: body, encoding: .utf8),
              let root = try? RawCommandEnvelope.fields(in: text),
              let rawError = root["error"],
              let error = try? RawCommandEnvelope.fields(in: rawError) else { return nil }
        func string(_ key: String) -> String? {
            error[key].flatMap { try? JSONDecoder().decode(String.self, from: Data($0.utf8)) }
        }
        // Keep the account provider's code-before-type precedence.
        switch string("code") ?? string("type") {
        case "insufficient_quota": return .quotaExhausted
        case "rate_limit_exceeded": return .rateLimited
        case "subscription_sharing_usage_limit_exceeded": return .planLimitReached
        default: return nil
        }
    }

    /// Normalize delta-seconds or IMF-fixdate to bounded seconds. Invalid/oversized values
    /// are labelled, never echoed or clamped into a misleading retry recommendation.
    private static func retryAfter(_ raw: String?, now: Date) -> (RetryAfterKind, Int?) {
        guard let raw else { return (.absent, nil) }
        guard raw.utf8.count <= 64 else { return (.invalid, nil) }
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        let maximum = 31_536_000 // One year; this is diagnostic metadata, never a retry timer.
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let seconds = Int(value), seconds <= maximum else { return (.invalid, nil) }
            return (.delaySeconds, seconds)
        }
        guard value.utf8.count == 29 else { return (.invalid, nil) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return (.invalid, nil) }
        let delay = max(0, ceil(date.timeIntervalSince(now)))
        guard delay.isFinite, delay <= Double(maximum) else { return (.invalid, nil) }
        return (.httpDate, Int(delay))
    }
}

/// One request's deadline decision, shared only with its diagnostic reader. HTTP 429 is
/// terminal here (never a streaming fallback), so keep it latched through the handoff
/// from inspection to validation. A new bounded request always gets a fresh instance.
/// Caller cancellation still wins via Task.checkCancellation and existing sanitization.
/// Other errors/deadlines are never remapped; this stores no response or provider data.
final class ModelHTTPDiagnosticDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var known429 = false

    func record429() { lock.lock(); defer { lock.unlock() }; known429 = true }
    var errorAtDeadline: HTTPChatModelError {
        lock.lock(); defer { lock.unlock() }
        return known429 ? .httpStatus(429) : .timedOut
    }
}

/// Chat/completions formerly discarded every 429 body immediately. Read only a short,
/// complete body with a separate 500 ms budget; diagnostics must not turn rejection into
/// a ten-minute wait. On failure retain the HTTP status; cancellation still propagates.
enum ModelHTTPFailureBody {
    static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data? {
        let result = await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                do {
                    var data = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard data.count < ModelHTTPFailureDiagnostic.maximumBodyBytes else { return nil }
                        data.append(byte)
                    }
                    try Task.checkCancellation()
                    return data
                } catch { return nil }
            }
            group.addTask {
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return nil }
                bytes.task.cancel()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            bytes.task.cancel()
            return first
        }
        try Task.checkCancellation()
        return result
    }
}
