import Foundation

/// A host declaration about this exact endpoint and model, not proof that the
/// provider will accept an image. Unknown must never be interpreted as support.
public enum ModelVisionCapability: Sendable, Equatable {
    case unknown, unsupported, supported
}

/// An explicitly selected, transient input. This type does not read a file,
/// retain a URL or grant access to a filesystem. Image signatures are checked;
/// the caller must still decode/validate the image before offering it to a user.
public struct ModelAttachment: Sendable, Equatable {
    public static let maximumImageBytes = 5 * 1024 * 1024
    public static let maximumTextBytes = 32 * 1024

    enum Payload: Sendable, Equatable {
        case image(data: Data, mime: String)
        case text(String)
    }
    let payload: Payload
    private init(payload: Payload) { self.payload = payload }

    /// Accept only JPEG and PNG with matching signatures. This checks the
    /// format marker, not whether the entire image is decodable or safe to render.
    public static func image(data: Data, mimeType: String) throws -> ModelAttachment {
        guard mimeType == "image/jpeg" || mimeType == "image/png" else { throw ModelAttachmentError.invalidType }
        guard !data.isEmpty else { throw ModelAttachmentError.empty }
        guard data.count <= maximumImageBytes else { throw ModelAttachmentError.tooLarge }
        let signature: [UInt8] = mimeType == "image/png"
            ? [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] : [0xff, 0xd8, 0xff]
        guard data.starts(with: signature) else { throw ModelAttachmentError.invalidContent }
        return ModelAttachment(payload: .image(data: data, mime: mimeType))
    }

    /// Text must be complete UTF-8 and cannot contain NUL; no truncation or
    /// replacement decoding is performed. The size limit is in input bytes.
    public static func text(utf8 data: Data) throws -> ModelAttachment {
        guard !data.isEmpty else { throw ModelAttachmentError.empty }
        guard data.count <= maximumTextBytes else { throw ModelAttachmentError.tooLarge }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw ModelAttachmentError.invalidContent
        }
        return ModelAttachment(payload: .text(text))
    }
}

/// Content-free errors are safe to report without leaking input or endpoint.
public enum ModelAttachmentError: Error, LocalizedError, Sendable, Equatable {
    case invalidType, empty, tooLarge, invalidContent
    case visionUnknown, visionUnsupported
    case multipleAttachments, attachmentNotCurrentUserMessage, requestTooLarge
    case explicitSerializationRequired

    public var errorDescription: String? {
        switch self {
        case .invalidType: return "The attachment type is not supported."
        case .empty: return "The attachment is empty."
        case .tooLarge: return "The attachment exceeds the size limit."
        case .invalidContent: return "The attachment does not match its declared format."
        case .visionUnknown: return "Image support for this model is unknown."
        case .visionUnsupported: return "This model does not support images."
        case .multipleAttachments: return "Only one attachment is allowed per request."
        case .attachmentNotCurrentUserMessage: return "An attachment is only allowed on the current user message."
        case .requestTooLarge: return "The request containing the attachment exceeds the size limit."
        case .explicitSerializationRequired: return "Attachment messages require explicit model request serialization."
        }
    }
}
