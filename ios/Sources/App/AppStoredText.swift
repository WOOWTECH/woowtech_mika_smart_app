import AssistantBrowser
import AssistantSkills
import Foundation

/// The App's stores keep their notices and errors as Traditional Chinese text:
/// the harnesses check that text, and some of it is saved. Every such message
/// is one of the closed messages below, so it is shown in the App language
/// here; anything else (user or model content, text from elsewhere) is shown
/// unchanged.
extension AppLocalizer {
    func stored(_ text: String) -> String {
        AppText.storedMessage(text).map(self.text) ?? text
    }
}

extension AppText {
    static func storedMessage(_ text: String) -> AppText? {
        if let fixed = storedFixed.first(where: { $0.traditionalFallback == text }) { return fixed }
        for pattern in compiledPatterns {
            guard let match = pattern.expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            else { continue }
            var values: [Int: String] = [:]
            for (group, index) in pattern.order.enumerated() {
                guard let range = Range(match.range(at: group + 1), in: text) else { continue }
                values[index] = String(text[range])
            }
            if let message = pattern.make(StoredValues(values: values)) { return message }
        }
        return moduleMessage(text)
    }

    struct StoredValues {
        let values: [Int: String]
        func text(_ index: Int) -> String { values[index] ?? "" }
        func count(_ index: Int) -> Int? { values[index].flatMap { Int($0) } }
    }

    private struct StoredPattern {
        let expression: NSRegularExpression
        /// The placeholder number for each capture group, in order of appearance.
        let order: [Int]
        let make: (StoredValues) -> AppText?
    }

    /// Each sample's Traditional Chinese format, e.g. 「已讀取 %1$lld 位元組。」, as an anchored pattern.
    private static let compiledPatterns: [StoredPattern] = storedPatterns.compactMap { sample, make in
        let format = sample.traditionalFallback
        guard let placeholder = try? NSRegularExpression(pattern: #"%([0-9]+)\$(@|lld)"#) else { return nil }
        var pattern = "^", order: [Int] = [], last = format.startIndex
        for match in placeholder.matches(in: format, range: NSRange(format.startIndex..., in: format)) {
            guard let whole = Range(match.range, in: format), let number = Range(match.range(at: 1), in: format),
                  let kind = Range(match.range(at: 2), in: format), let index = Int(format[number]) else { return nil }
            pattern += NSRegularExpression.escapedPattern(for: String(format[last..<whole.lowerBound]))
            pattern += format[kind] == "@" ? "(.+?)" : "(-?[0-9]+)"
            order.append(index); last = whole.upperBound
        }
        pattern += NSRegularExpression.escapedPattern(for: String(format[last...])) + "$"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        else { return nil }
        return StoredPattern(expression: expression, order: order, make: make)
    }

    /// The shared modules' own error descriptions, which the stores pass through as text.
    private static func moduleMessage(_ text: String) -> AppText? {
        if let error = skillExecutionErrors.first(where: { $0.errorDescription == text }) { return skillExecutionError(error) }
        let catalog: [SkillCatalogError] = [.unavailable, .invalidCatalog, .notFound, .alreadyAdded]
        if let error = catalog.first(where: { $0.errorDescription == text }) { return AppLocalizer.skillCatalogError(error) }
        return downloadMessage(text)
    }

    private static let storedFixed: [AppText] = [
        .learningUnavailable, .learningProfileSaved, .learningProcedureApproved, .learningProcedureDeclined,
        .learningCleared, .learningClearedKeyPending, .learningForgot, .learningDeleted, .learningUseCountFailed,
        .learningTidyUnconfirmed, .learningTidyConflict, .learningTidyBusy, .learningTidyFailed,
        .learningWebNotSaved, .learningNotSaved, .learningSkillRecordFailed, .learningBusy, .learningConflict,
        .learningProfileInvalidSentence, .learningProfileDuplicate, .learningProfileFull,
        .learningProfileMatchNotUnique, .learningProfileInvalidState, .learningSkillNotSaved,
        .learningBuiltinNotImported, .learningMemorySensitive, .learningMemoryInvalid, .learningMemoryFull,
        .learningMemoryDuplicate, .learningMemoryStale, .learningMemoryFailed, .learningSkillUnknownTool,
        .learningSkillSensitive, .learningSkillChanged, .learningSkillDraftPending, .learningSkillBuiltinName,
        .learningSkillMissingSection, .learningSkillTooLong, .learningSkillCapacity, .learningSkillInvalid,
        .learningSaveFailed, .archiveDeleteNotSaved, .archiveReadFailed,
        // Default titles the browser library gives tabs it has no page title for.
        .browserTabNew, .browserTabSignIn, .browserTabPage,
    ]

    private static let storedPatterns: [(AppText, (StoredValues) -> AppText?)] = [
        (.learningRemembered(value: ""), { .learningRemembered(value: $0.text(1)) }),
        (.learningUpdated(value: ""), { .learningUpdated(value: $0.text(1)) }),
        (.learningPendingProcedure(value: ""), { .learningPendingProcedure(value: $0.text(1)) }),
    ]
}
