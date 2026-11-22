import Foundation

/// The client a provider's kind chooses: HTTPChatModelClient (chat/completions with the API key)
/// for OpenAI-compatible providers, ResponsesModelClient (with the account's token) for a
/// configuration that names a signed-in account. An account configuration never reaches
/// chat/completions, and an API-key configuration never reaches Responses.
public struct ModelProviderClient: StructuredStreamingChatModelClient, ReferenceDispatchBoundStreamingChatModelClient {
    private let http: HTTPChatModelClient
    private let responses: ResponsesModelClient?

    public init(accounts: (any ModelAccountTokenProviding)?, usageSink: (any ModelUsageSink)? = nil) {
        http = HTTPChatModelClient(usageSink: usageSink)
        responses = accounts.map { ResponsesModelClient(accounts: $0, usageSink: usageSink) }
    }

    public init(http: HTTPChatModelClient, responses: ResponsesModelClient?) {
        self.http = http; self.responses = responses
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        guard configuration.account != nil else {
            return try await http.complete(messages: messages, configuration: configuration, apiKey: apiKey)
        }
        guard let responses else { throw HTTPChatModelError.invalidConfiguration }
        return try await responses.complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                         onDispatch: @escaping @Sendable () -> Void) async throws -> String {
        guard configuration.account != nil else {
            return try await http.complete(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: onDispatch)
        }
        guard let responses else { throw HTTPChatModelError.invalidConfiguration }
        return try await responses.complete(messages: messages, configuration: configuration, apiKey: apiKey, onDispatch: onDispatch)
    }

    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        guard configuration.account != nil else { return http.stream(messages: messages, configuration: configuration, apiKey: apiKey) }
        guard let responses else { return Self.refused() }
        return responses.stream(messages: messages, configuration: configuration, apiKey: apiKey)
    }

    public func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                       onDispatch: @escaping @Sendable () -> Void,
                       onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error> {
        guard configuration.account != nil else {
            return http.stream(messages: messages, configuration: configuration, apiKey: apiKey,
                               onDispatch: onDispatch, onProducerFinished: onProducerFinished)
        }
        guard let responses else {
            onProducerFinished()
            return Self.refused()
        }
        return responses.stream(messages: messages, configuration: configuration, apiKey: apiKey,
                                onDispatch: onDispatch, onProducerFinished: onProducerFinished)
    }

    private static func refused() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: HTTPChatModelError.invalidConfiguration) }
    }
}
