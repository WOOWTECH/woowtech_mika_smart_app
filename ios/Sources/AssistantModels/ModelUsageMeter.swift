import Foundation

/// What a model request was for. Only a ledger dimension; never shown.
public enum ModelUsagePurpose: String, Sendable, CaseIterable {
    case chat, memory, browser, skill, other
}

/// The model replies of one run, like Android's RunUsageTally. Only fully
/// validated replies are recorded; failed, cut or cancelled requests never are.
public final class ModelUsageTally: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// Validated replies, and how many of them carried no usable report.
        public internal(set) var replies: Int
        public internal(set) var unreported: Int
        /// Input includes cache hits and output includes reasoning, as on Android.
        public internal(set) var input: Int64
        public internal(set) var output: Int64
        public internal(set) var cached: Int64

        public init(replies: Int = 0, unreported: Int = 0, input: Int64 = 0, output: Int64 = 0, cached: Int64 = 0) {
            self.replies = replies; self.unreported = unreported
            self.input = input; self.output = output; self.cached = cached
        }
    }

    private let lock = NSLock()
    private var current = Snapshot()
    private var sealed = false

    public init() {}

    /// One validated reply. Without an input count it is unreported.
    public func record(_ usage: ModelTokenUsage?) {
        lock.lock(); defer { lock.unlock() }
        guard !sealed else { return }
        current.replies += 1
        guard let usage, let input = usage.inputTokens else { current.unreported += 1; return }
        current.input = Self.add(current.input, input)
        current.output = Self.add(current.output, usage.outputTokens ?? 0)
        current.cached = Self.add(current.cached, usage.cachedInputTokens ?? 0)
    }

    /// The final count. Later records are ignored, so a late reply cannot
    /// change a published turn.
    public func seal() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        sealed = true
        return current
    }

    private static func add(_ total: Int64, _ count: Int) -> Int64 {
        let (sum, overflow) = total.addingReportingOverflow(Int64(count))
        return overflow ? .max : sum
    }
}

/// Task-local metering, read by HTTPChatModelClient when a request is made.
/// Values follow child tasks and `Task {}` but not `Task.detached`: a model
/// call moved to a detached task is silently left out of the run's tally.
public enum ModelUsageScope {
    @TaskLocal public static var tally: ModelUsageTally?
    @TaskLocal public static var purpose: ModelUsagePurpose = .other
    /// False for connection tests, which Android does not meter either.
    @TaskLocal public static var metered: Bool = true

    /// For test clients that bypass HTTP: one validated reply, recorded as
    /// HTTPChatModelClient would record it.
    public static func reply(_ usage: ModelTokenUsage?) {
        guard metered else { return }
        tally?.record(usage)
    }
}

/// One request as the transport saw it; no text, key, header or body.
public struct ModelUsageEvent: Sendable, Equatable {
    public let baseURL: URL
    public let model: String
    public let purpose: ModelUsagePurpose
    /// Nil when the request failed, was cut or cancelled, or carried no report.
    public let usage: ModelTokenUsage?
    /// False only when the request was never handed to URLSession.
    public let dispatched: Bool
    public let at: Date

    public init(baseURL: URL, model: String, purpose: ModelUsagePurpose, usage: ModelTokenUsage?,
                dispatched: Bool, at: Date) {
        self.baseURL = baseURL; self.model = model; self.purpose = purpose
        self.usage = usage; self.dispatched = dispatched; self.at = at
    }
}

/// Receives every metered request once, failed ones included (Android's
/// UsageSink). Called on the transport's task; keep it quick.
public protocol ModelUsageSink: Sendable {
    func record(_ event: ModelUsageEvent)
}

/// One request's metering. The caller's scope is read when the request is
/// made, and the outcome is reported exactly once, however the request ends.
final class ModelUsageMeter: @unchecked Sendable {
    private let tally: ModelUsageTally?
    private let sink: (any ModelUsageSink)?
    private let baseURL: URL
    private let model: String
    private let purpose: ModelUsagePurpose
    private let lock = NSLock()
    private var handed = false
    private var reported = false

    init(sink: (any ModelUsageSink)?, configuration: ModelConfiguration) {
        let metered = ModelUsageScope.metered
        tally = metered ? ModelUsageScope.tally : nil
        self.sink = metered ? sink : nil
        purpose = ModelUsageScope.purpose
        baseURL = configuration.baseURL
        model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The request is being handed to URLSession.
    func dispatching() {
        lock.lock(); defer { lock.unlock() }
        handed = true
    }

    /// A fully validated reply: the run's tally, then the sink.
    func succeeded(_ usage: ModelTokenUsage?) {
        guard finish() != nil else { return }
        tally?.record(usage)
        sink?.record(.init(baseURL: baseURL, model: model, purpose: purpose, usage: usage, dispatched: true, at: Date()))
    }

    /// Failed, cut, timed out or cancelled: only the sink, without usage.
    func failed() {
        guard let dispatched = finish() else { return }
        sink?.record(.init(baseURL: baseURL, model: model, purpose: purpose, usage: nil, dispatched: dispatched, at: Date()))
    }

    /// Whether the request was handed over; nil after the first outcome.
    private func finish() -> Bool? {
        lock.lock(); defer { lock.unlock() }
        guard !reported else { return nil }
        reported = true
        return handed
    }
}
