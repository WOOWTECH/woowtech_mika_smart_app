import CryptoKit
import Foundation

public struct ModelConfiguration: Sendable {
    public let baseURL: URL
    public let model: String
    public let maxOutputTokens: Int
    public let vision: ModelVisionCapability
    /// False only for a custom OpenAI-compatible service saved without a key
    /// (Android AddForm.keyRequired): a blank key then sends no Authorization
    /// header. Every preset needs a key.
    public let requiresKey: Bool
    /// The header this provider requires on every request, with this
    /// conversation's value (OpenCode Go: x-opencode-session); nil sends none.
    public let sessionHeader: ModelSessionHeader?

    public init(baseURL: URL, model: String, maxOutputTokens: Int = 1024,
                vision: ModelVisionCapability = .unknown, requiresKey: Bool = true,
                sessionHeader: ModelSessionHeader? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.vision = vision
        self.requiresKey = requiresKey
        self.sessionHeader = sessionHeader
    }

    /// The same destination, key rule and session header with another output limit.
    public func withMaxOutputTokens(_ tokens: Int) -> ModelConfiguration {
        ModelConfiguration(baseURL: baseURL, model: model, maxOutputTokens: tokens, vision: vision,
                           requiresKey: requiresKey, sessionHeader: sessionHeader)
    }
}

public struct ModelMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    /// Transient input only. They are never implicitly archived or Codable.
    public let attachments: [ModelAttachment]
    public var attachment: ModelAttachment? { attachments.first }

    public init(role: String, content: String) {
        self.role = role
        self.content = content
        self.attachments = []
    }

    public init(userText: String, attachment: ModelAttachment) {
        self.init(userText: userText, attachments: [attachment])
    }

    /// The attachments the user picked for this prompt, in the order shown.
    public init(userText: String, attachments: [ModelAttachment]) {
        role = "user"; content = userText; self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        content = try values.decode(String.self, forKey: .content)
        attachments = []
    }

    public func encode(to encoder: Encoder) throws {
        guard attachments.isEmpty else { throw ModelAttachmentError.explicitSerializationRequired }
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

/// A structured provider error explicitly identifying `stream` as unsupported,
/// or a short error naming `stream_options`. Kept separate from
/// HTTPChatModelError so the host can permit one bounded, content-free
/// fallback without guessing from a status code. The client never resends.
public enum HTTPStreamFallbackError: Error, LocalizedError, Sendable, Equatable {
    case explicitUnsupported(Int)
    /// The endpoint streams but refused the usage option. The client already
    /// leaves it out for this endpoint and model, so one resend can succeed.
    case usageOptionUnsupported(Int)

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

/// A header some providers require on every request, as Android's
/// ClientHeaders and ModelSession (core model/ClientHeaders.kt): OpenCode Go
/// rejects a request without x-opencode-session (HTTP 400) and uses it to keep
/// one conversation's requests together. The value comes from the conversation
/// id and never reveals it; a request outside a conversation (a connection
/// test, one browser research run) gets a fresh value.
public struct ModelSessionHeader: Equatable, Sendable {
    public let name: String
    public let value: String

    /// Nil unless `name` is an HTTP token iOS may send (not one of the
    /// request's own headers) and `value` is one short line of visible ASCII.
    public init?(name: String, value: String) {
        guard Self.isAllowed(name: name, value: value) else { return nil }
        self.name = name; self.value = value
    }

    /// Android ModelSession.of: the same value for every request of one
    /// conversation, another for another conversation. Like Java's
    /// UUID.nameUUIDFromBytes, a version 3 UUID of "mika-conversation:<id>".
    public static func conversation(_ conversationID: String, name: String) -> ModelSessionHeader? {
        var bytes = Array(Insecure.MD5.hash(data: Data(("mika-conversation:" + conversationID).utf8)))
        bytes[6] = (bytes[6] & 0x0f) | 0x30
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return ModelSessionHeader(name: name, value: uuid.uuidString.lowercased())
    }

    /// Android ModelSession.fresh: a request that belongs to no conversation.
    public static func fresh(name: String) -> ModelSessionHeader? {
        ModelSessionHeader(name: name, value: UUID().uuidString.lowercased())
    }

    /// Headers the request sets itself, or that a server or proxy treats as
    /// part of the connection; a provider's session header is never one of them.
    static let reservedNames: Set<String> = [
        "accept", "accept-encoding", "authorization", "connection", "content-length", "content-type", "cookie",
        "expect", "host", "keep-alive", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade",
        "user-agent",
    ]

    static func isAllowed(name: String, value: String) -> Bool {
        isToken(name) && !reservedNames.contains(name.lowercased())
            && (1...256).contains(value.utf8.count) && value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }

    /// An HTTP token (RFC 9110) of 1–64 bytes, so a name cannot inject another header.
    static func isToken(_ name: String) -> Bool {
        let extra = Set("!#$%&'*+-.^_`|~".utf8)
        return (1...64).contains(name.utf8.count) && name.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || extra.contains(byte)
        }
    }
}
