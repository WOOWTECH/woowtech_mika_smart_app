import Foundation

/// A building block for a future reviewed tool turn. It is deliberately not
/// wired into chat: the host must still fence the reviewed state and retain its
/// archive lease through the actual transport lifetime, including cancellation.
/// This wrapper only prevents an attachment from being automatically replayed.
/// It cannot prevent a model from copying attachment-derived data into a tool
/// proposal or a later response; such proposals require their own review.
public actor OneShotAttachmentModelClient: ChatModelClient {
    private enum Phase { case fresh, requesting, ready, ended }
    private var phase = Phase.fresh
    private var attachment: ModelAttachment?
    private var previousMessages: [ModelMessage]?
    private let client: any LifetimeBoundCompletionChatModelClient
    private let reviewedMessages: [ModelMessage]
    private let configuration: ModelConfiguration
    private let key: String

    /// `reviewedMessages` is the exact host-reviewed input before the tool
    /// runner adds its protocol instructions and catalog. It contains no
    /// attachment itself and ends with the user's composed prompt.
    public init(client: any LifetimeBoundCompletionChatModelClient, attachment: ModelAttachment,
                reviewedMessages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) throws {
        guard !reviewedMessages.isEmpty, reviewedMessages.last?.role == "user",
              reviewedMessages.allSatisfy({ $0.attachment == nil }), !apiKey.isEmpty else {
            throw OneShotAttachmentError.invalidInput
        }
        self.client = client; self.attachment = attachment; self.reviewedMessages = reviewedMessages
        self.configuration = configuration; self.key = apiKey
    }

    public func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        guard phase != .requesting else { throw OneShotAttachmentError.requestInProgress }
        guard phase != .ended else { throw OneShotAttachmentError.ended }
        do {
            try Task.checkCancellation()
            guard configuration.baseURL == self.configuration.baseURL,
                  configuration.model == self.configuration.model,
                  configuration.maxOutputTokens == self.configuration.maxOutputTokens,
                  configuration.vision == self.configuration.vision, apiKey == key,
                  messages.allSatisfy({ $0.attachment == nil }) else {
                throw OneShotAttachmentError.contextChanged
            }
            if let previousMessages {
                guard messages.count > previousMessages.count,
                      messages.prefix(previousMessages.count).elementsEqual(previousMessages) else {
                    throw OneShotAttachmentError.contextChanged
                }
            } else {
                // Only the first request needs to locate the reviewed input.
                // Later calls pin the entire prior transcript as an unchanged
                // prefix, so a new tool result may legitimately repeat it.
                guard Self.containsExactlyOnce(reviewedMessages, in: messages) else {
                    throw OneShotAttachmentError.contextChanged
                }
            }
            var outgoing = messages
            if phase == .fresh {
                guard let last = outgoing.last, last.role == "user", let selected = attachment else {
                    throw OneShotAttachmentError.invalidInput
                }
                outgoing[outgoing.count - 1] = ModelMessage(userText: last.content, attachment: selected)
                // Consume before crossing the async boundary: even an error or
                // cancellation may mean the server received the first request.
                attachment = nil
            }
            previousMessages = messages
            phase = .requesting
            let reply = try await client.complete(messages: outgoing, configuration: configuration, apiKey: apiKey)
            try Task.checkCancellation()
            guard phase == .requesting else { throw CancellationError() }
            phase = .ready
            return reply
        } catch {
            attachment = nil; previousMessages = nil; phase = .ended
            throw error
        }
    }

    /// Ends the turn and clears any attachment not yet consumed. An in-flight
    /// client must also be cancelled by its owning task; this is not a transport
    /// cancellation or a substitute for the host's lifetime guard.
    public func cancel() { attachment = nil; previousMessages = nil; phase = .ended }

    private static func containsExactlyOnce(_ needle: [ModelMessage], in haystack: [ModelMessage]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        var count = 0
        for start in 0...(haystack.count - needle.count) {
            if haystack[start..<(start + needle.count)].elementsEqual(needle) {
                count += 1
                if count > 1 { return false }
            }
        }
        return count == 1
    }
}

/// Fixed categories contain no file contents, destination, or credential.
public enum OneShotAttachmentError: Error, Sendable, Equatable {
    case invalidInput, contextChanged, requestInProgress, ended
}
