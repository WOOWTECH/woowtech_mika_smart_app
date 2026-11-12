import Foundation

public struct ModelConfiguration: Sendable {
    public let baseURL: URL
    public let model: String
    public let maxOutputTokens: Int
    public let vision: ModelVisionCapability

    public init(baseURL: URL, model: String, maxOutputTokens: Int = 1024,
                vision: ModelVisionCapability = .unknown) {
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.vision = vision
    }
}

public struct ModelMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    /// Transient input only. It is never implicitly archived or Codable.
    public let attachment: ModelAttachment?

    public init(role: String, content: String) {
        self.role = role
        self.content = content
        self.attachment = nil
    }

    public init(userText: String, attachment: ModelAttachment) {
        role = "user"; content = userText; self.attachment = attachment
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        content = try values.decode(String.self, forKey: .content)
        attachment = nil
    }

    public func encode(to encoder: Encoder) throws {
        guard attachment == nil else { throw ModelAttachmentError.explicitSerializationRequired }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role, forKey: .role)
        try values.encode(content, forKey: .content)
    }
}

public protocol ChatModelClient: Sendable {
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String
}

/// `onDispatch` may run only after this exact request has begun dispatching.
/// If it never runs, returning or throwing must mean no producer can start it
/// later. No automatic retries or detached future requests are allowed.
public protocol ReferenceDispatchBoundChatModelClient: ChatModelClient {
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                  onDispatch: @escaping @Sendable () -> Void) async throws -> String
}

/// Optional text-delta capability. Finishing normally certifies a complete reply;
/// truncation, cancellation and provider errors must finish by throwing.
/// Structured tool flows use this only when separately opted in and keep their
/// existing whole-command validators before any tool effect or final answer.
public protocol StreamingChatModelClient: ChatModelClient {
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error>
}

/// Explicit capability for streaming a structured tool-command response. The
/// host must parse the complete command before acting and may preview only a
/// recognized, decoded finish.answer field. Plain-only fixtures stay on complete.
public protocol StructuredStreamingChatModelClient: StreamingChatModelClient {}

/// A stream producer must call `onProducerFinished` only after it can no
/// longer start or continue this request, including after consumer cancellation.
/// `onDispatch` has the same meaning as for the complete-only capability.
public protocol ReferenceDispatchBoundStreamingChatModelClient: StreamingChatModelClient, ReferenceDispatchBoundChatModelClient {
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                onDispatch: @escaping @Sendable () -> Void,
                onProducerFinished: @escaping @Sendable () -> Void) -> AsyncThrowingStream<String, Error>
}

/// A structured provider error explicitly identifying `stream` as unsupported.
/// Kept separate from HTTPChatModelError so the host can permit one bounded,
/// content-free complete fallback without guessing from a status code.
public enum HTTPStreamFallbackError: Error, LocalizedError, Sendable, Equatable {
    case explicitUnsupported(Int)

    public var errorDescription: String? { "The model endpoint rejected the initial streaming request." }
}

/// Deliberately excludes response bodies, credentials and endpoint URLs.
public enum HTTPChatModelError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case redirectRejected
    case httpStatus(Int)
    case invalidResponse
    case incompleteResponse
    case responseTooLarge
    case consumerTooSlow
    case timedOut
    case transportFailure

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Check the HTTPS endpoint, model, API key and output token limit (1–8192)."
        case .redirectRejected: return "The model endpoint attempted a redirect."
        case .httpStatus(let status): return "The model request failed (HTTP \(status))."
        case .invalidResponse: return "The model returned an invalid response."
        case .incompleteResponse: return "The model response ended before completion."
        case .responseTooLarge: return "The model response exceeded the size limit."
        case .consumerTooSlow: return "The model stream exceeded the pending output limit."
        case .timedOut: return "The model request exceeded its time limit."
        case .transportFailure: return "The model connection failed."
        }
    }
}
