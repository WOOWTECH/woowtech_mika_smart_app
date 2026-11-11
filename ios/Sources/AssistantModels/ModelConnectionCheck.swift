import Foundation

/// One explicit, isolated text completion. No conversation, tools or settings
/// are read or written here. Only fixed error categories leave this boundary.
@MainActor
public final class ModelConnectionCheck {
    public enum Failure: Equatable, Sendable {
        case credentials, configuration, authentication, notFound, rateLimited
        case server, rejected, response, redirect, timeout, network
    }
    public enum State: Equatable, Sendable {
        case untested, testing, passed, failed(Failure)
    }

    public private(set) var state: State = .untested {
        didSet { onChange?(state) }
    }
    public var onChange: ((State) -> Void)?
    #if DEBUG
    /// A UI fixture can observe the end of the worker after cancellation.
    /// Never carries the request, response, endpoint, or credential.
    public var onFixtureAttemptSettled: (() -> Void)?
    #endif
    private var generation: UInt64 = 0
    private var operation: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private let timeoutNanoseconds: UInt64

    public init(timeoutNanoseconds: UInt64 = 20_000_000_000) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    /// Invalidate before cancellation so even a non-cooperative client cannot
    /// publish a stale success or failure into a later test.
    public func reset() {
        let current = invalidate()
        guard generation == current else { return }
        if state != .untested { state = .untested }
    }

    private func invalidate() -> UInt64 {
        generation &+= 1
        let current = generation
        let oldOperation = operation; operation = nil
        let oldTimer = timer; timer = nil
        oldOperation?.cancel()
        oldTimer?.cancel()
        return current
    }

    public func credentialsUnavailable() {
        let previous = generation
        reset()
        guard generation == previous &+ 1, state == .untested else { return }
        state = .failed(.credentials)
    }

    public func start(client: any ChatModelClient, configuration: ModelConfiguration, apiKey: String) {
        let current = invalidate()
        guard generation == current else { return }
        state = .testing
        guard generation == current, state == .testing else { return }
        let probe = ModelConfiguration(baseURL: configuration.baseURL, model: configuration.model,
                                       maxOutputTokens: 32)
        #if DEBUG
        let fixtureSettled = onFixtureAttemptSettled
        #endif
        operation = Task { [weak self] in
            #if DEBUG
            defer { fixtureSettled?() }
            #endif
            do {
                let reply = try await client.complete(
                    messages: [ModelMessage(role: "user", content: "This is a connection test. Reply briefly.")],
                    configuration: probe, apiKey: apiKey)
                try Task.checkCancellation()
                let result: State = reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .failed(.response) : .passed
                self?.finish(result, generation: current)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finish(.failed(Self.classify(error)), generation: current)
            }
        }
        timer = Task { [weak self, timeoutNanoseconds] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            self?.finish(.failed(.timeout), generation: current)
        }
    }

    private func finish(_ result: State, generation current: UInt64) {
        guard generation == current, state == .testing else { return }
        let next = invalidate()
        guard generation == next else { return }
        state = result
    }

    private static func classify(_ error: Error) -> Failure {
        guard let error = error as? HTTPChatModelError else { return .network }
        switch error {
        case .invalidConfiguration: return .configuration
        case .httpStatus(let code):
            switch code {
            case 401, 403: return .authentication
            case 404: return .notFound
            case 429: return .rateLimited
            case 500...599: return .server
            default: return .rejected
            }
        case .timedOut: return .timeout
        case .invalidResponse, .incompleteResponse, .responseTooLarge: return .response
        case .redirectRejected: return .redirect
        case .consumerTooSlow, .transportFailure: return .network
        }
    }
}
