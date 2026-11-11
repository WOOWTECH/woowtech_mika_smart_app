import AssistantAttachments
import Foundation

private struct Failure: Error { let detail: String }
private var checks = 0
private func check(_ value: @autoclosure () -> Bool, _ detail: String) throws {
    checks += 1
    if !value() { throw Failure(detail: detail) }
}
@main struct CheckChatAttachmentLocalization {
    static func main() throws {
        guard let bundle = Bundle(path: CommandLine.arguments[1]) else { throw Failure(detail: "Fixture bundle missing") }
        let errors: [ChatAttachmentPresentationError] = [
            .pickerFailed, .invalidContext, .contextChanged, .confirmationRequired, .visionUnknown, .visionUnsupported,
            .importing(.invalidSelection), .importing(.unsupportedType), .importing(.unreadable), .importing(.tooLarge),
            .importing(.empty), .importing(.invalidFormat), .importing(.imageTooLarge), .importing(.cancelled),
            .importing(.timedOut), .importing(.invalidState)
        ]
        let types: [ChatAttachmentKind] = [.jpeg, .png, .text]
        let fixed: [AppText] = [
            .attachmentTitle, .attachmentLocalNotice, .attachmentLimits, .attachmentSection, .attachmentConsumed,
            .attachmentEmpty, .attachmentLoading, .attachmentConfirmed, .attachmentTaking, .attachmentSelect,
            .attachmentReplace, .attachmentRemove, .attachmentReview, .attachmentSendNotice, .attachmentConfirm,
            .attachmentNeedsContext, .attachmentDone, .attachmentDataNone, .attachmentDataSeparator,
            .attachmentModel(value: "fixture"), .attachmentOtherData(value: "fixture")
        ]
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language, bundle: bundle)
            for key in fixed {
                let text = localizer.resolve(key)
                try check(!text.usedFallback && text.language == language && !text.text.isEmpty, "Picker UI translation missing")
            }
            for error in errors {
                let text = localizer.resolve(AppLocalizer.attachmentError(error))
                try check(!text.usedFallback && text.language == language && !text.text.isEmpty, "Error translation missing")
            }
            for kind in types {
                let text = localizer.resolve(AppLocalizer.attachmentKind(kind))
                try check(!text.usedFallback && text.language == language && !text.text.isEmpty, "Type translation missing")
            }
            for category in ChatAttachmentAdditionalData.allCases {
                let text = localizer.resolve(AppLocalizer.attachmentData(category))
                try check(!text.usedFallback && text.language == language && !text.text.isEmpty, "Disclosure translation missing")
            }
            let label = localizer.attachmentDataDescription([.currentQuestion, .memory])
            let expected: String
            switch language {
            case .traditionalChinese: expected = "本次問題、相關記憶"
            case .simplifiedChinese: expected = "本次问题、相关记忆"
            case .english: expected = "Current question, Relevant memories"
            }
            try check(label == expected, "Disclosure language/order/separator")
            try check(localizer.attachmentDataDescription([]) == localizer.text(.attachmentDataNone), "Empty disclosure translated")
            let input = "example.invalid/%@/檔案"
            let destination = localizer.resolve(.attachmentDestination(value: input))
            try check(!destination.usedFallback && destination.text.contains(input), "Destination remains verbatim")
            let metadata = localizer.resolve(.attachmentMetadata(count: 123, kind: localizer.text(.attachmentKindPNG)))
            try check(!metadata.usedFallback && metadata.text.contains("123") && metadata.text.contains("PNG"), "Size/type parameterized")
        }
        print("Chat attachment localization checks passed: \(checks)")
    }
}
