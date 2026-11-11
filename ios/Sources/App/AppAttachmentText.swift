import AssistantAttachments
import Foundation

/// Closed adapters keep file/provider data out of localization keys and avoid
/// exposing localized descriptions from arbitrary errors.
extension AppLocalizer {
    static func attachmentError(_ error: ChatAttachmentPresentationError) -> AppText {
        switch error {
        case .pickerFailed: return .attachmentErrorPicker
        case .invalidContext: return .attachmentErrorContext
        case .contextChanged: return .attachmentErrorContextChanged
        case .confirmationRequired: return .attachmentErrorConfirmation
        case .visionUnknown: return .attachmentErrorVisionUnknown
        case .visionUnsupported: return .attachmentErrorVisionUnsupported
        case .importing(let reason):
            switch reason {
            case .invalidSelection: return .attachmentErrorSelection
            case .unsupportedType: return .attachmentErrorType
            case .unreadable: return .attachmentErrorRead
            case .tooLarge: return .attachmentErrorTooLarge
            case .empty: return .attachmentErrorEmpty
            case .invalidFormat: return .attachmentErrorFormat
            case .imageTooLarge: return .attachmentErrorImageSize
            case .cancelled: return .attachmentErrorCancelled
            case .timedOut: return .attachmentErrorTimeout
            case .invalidState: return .attachmentErrorState
            }
        }
    }

    static func attachmentKind(_ kind: ChatAttachmentKind) -> AppText {
        switch kind {
        case .jpeg: return .attachmentKindJPEG
        case .png: return .attachmentKindPNG
        case .text: return .attachmentKindText
        }
    }

    static func attachmentData(_ category: ChatAttachmentAdditionalData) -> AppText {
        switch category {
        case .systemInstructions: return .attachmentDataSystem
        case .currentQuestion: return .attachmentDataQuestion
        case .conversationHistory: return .attachmentDataHistory
        case .profile: return .attachmentDataProfile
        case .memory: return .attachmentDataMemory
        case .skills: return .attachmentDataSkills
        case .toolData: return .attachmentDataTools
        }
    }

    func attachmentDataDescription(_ data: Set<ChatAttachmentAdditionalData>) -> String {
        let labels = ChatAttachmentAdditionalData.allCases.filter { data.contains($0) }.map { text(Self.attachmentData($0)) }
        return labels.isEmpty ? text(.attachmentDataNone) : labels.joined(separator: text(.attachmentDataSeparator))
    }
}
