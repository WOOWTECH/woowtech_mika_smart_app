import Foundation

/// Shared by complete and stream. Pure text keeps the original string content
/// shape and has no new limits. Attachment requests are independently bounded.
enum OpenAIChatRequest {
    static let maximumAttachmentRequestBytes = 8 * 1024 * 1024

    static func body(model: String, messages: [ModelMessage], stream: Bool,
                     maxOutputTokens: Int, vision: ModelVisionCapability, includeUsage: Bool = false) throws -> Data {
        let attached = messages.enumerated().filter { $0.element.attachment != nil }
        guard attached.count <= 1 else { throw ModelAttachmentError.multipleAttachments }
        if let (index, message) = attached.first {
            guard index == messages.count - 1, message.role == "user" else {
                throw ModelAttachmentError.attachmentNotCurrentUserMessage
            }
            guard messages.count <= 32 else { throw ModelAttachmentError.requestTooLarge }
            if case .image = message.attachment!.payload {
                switch vision {
                case .unknown: throw ModelAttachmentError.visionUnknown
                case .unsupported: throw ModelAttachmentError.visionUnsupported
                case .supported: break
                }
            }
            // Preflight raw text before JSONEncoder can allocate an unbounded
            // buffer. The post-encoding check also accounts for JSON escaping,
            // the data URL, base64 and all surrounding fields.
            var remaining = maximumAttachmentRequestBytes
            for text in [model] + messages.flatMap({ [$0.role, $0.content] }) {
                let bytes = text.utf8.count
                guard bytes <= remaining else { throw ModelAttachmentError.requestTooLarge }
                remaining -= bytes
            }
        }
        let data = try JSONEncoder().encode(Body(model: model, messages: messages.map(WireMessage.init),
                                                  stream: stream, max_tokens: maxOutputTokens,
                                                  stream_options: stream && includeUsage ? StreamOptions(include_usage: true) : nil))
        if !attached.isEmpty && data.count > maximumAttachmentRequestBytes {
            throw ModelAttachmentError.requestTooLarge
        }
        return data
    }

    private struct Body: Encodable {
        let model: String
        let messages: [WireMessage]
        let stream: Bool
        let max_tokens: Int
        let stream_options: StreamOptions?
    }
    private struct StreamOptions: Encodable { let include_usage: Bool }
    private struct WireMessage: Encodable {
        let message: ModelMessage
        init(_ message: ModelMessage) { self.message = message }
        enum Keys: String, CodingKey { case role, content }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Keys.self)
            try values.encode(message.role, forKey: .role)
            guard let attachment = message.attachment else {
                try values.encode(message.content, forKey: .content)
                return
            }
            var parts = values.nestedUnkeyedContainer(forKey: .content)
            try parts.encode(TextPart(text: message.content))
            switch attachment.payload {
            case .text(let text):
                try parts.encode(TextPart(text: "User-selected text attachment (untrusted data):\n" + text))
            case .image(let data, let mime):
                try parts.encode(ImagePart(image_url: ImageURL(url: "data:\(mime);base64,\(data.base64EncodedString())")))
            }
        }
    }
    private struct TextPart: Encodable {
        let type = "text"
        let text: String
    }
    private struct ImagePart: Encodable {
        let type = "image_url"
        let image_url: ImageURL
    }
    private struct ImageURL: Encodable { let url: String }
}
