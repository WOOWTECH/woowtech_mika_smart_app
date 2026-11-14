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
        if let message = AppText.storedMessage(text) { return self.text(message) }
        // A stored message followed by one of the closed tails. The Traditional
        // Chinese text is already what the store wrote, so only English joins parts.
        guard language == .english else { return text }
        for suffix in AppText.storedSuffixes {
            let tail = suffix.traditionalFallback
            guard text.hasSuffix(tail) else { continue }
            let head = String(text.dropLast(tail.count))
            let translatedTail = self.text(suffix).trimmingCharacters(in: .whitespaces)
            if head.trimmingCharacters(in: .whitespaces).isEmpty { return translatedTail }
            guard let first = AppText.storedMessage(head) else { continue }
            return self.text(first) + " " + translatedTail
        }
        return text
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
        if let error = skillAuthoringErrors.first(where: { $0.errorDescription == text }) { return skillAuthoringError(error) }
        if let error = skillToolErrors.first(where: { $0.errorDescription == text }) { return skillToolError(error) }
        return nil
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
        // Chat, browser and module messages shown on the chat and browser screens.
        .storedChatPartialReceiving, .storedChatPartialCancelled, .storedChatPartialFailed,
        .storedChatSettingsChanged, .storedChatArchiveOpened, .storedChatArchiveSaveFailed,
        .storedChatQuoteBeforeChange, .storedChatQuoteBeforeRemove, .storedChatQuoteChanged,
        .storedChatArchiveChanged, .storedChatMcpNotReady, .storedChatKeyUnreadable, .storedChatLearningUnreadable,
        .storedChatPrepareFailed, .storedChatEmptyReply, .storedChatNoSingleStep, .storedChatSendFailed,
        .storedChatMcpUnfinished, .storedChatMemorySavedReplyUnfinished, .storedChatProfileSavedReplyUnfinished,
        .storedChatReasonAuth, .storedChatReasonRateLimited, .storedChatReasonUnavailable, .storedChatReasonRefused,
        .storedChatReasonTimeout, .storedChatReasonOffline, .storedChatReasonToolsOff, .storedChatReasonToolExpired,
        .storedChatReasonToolIncomplete, .storedChatCancelledWait, .storedChatLearningBusy,
        .storedChatLearningChanged, .storedChatLearningSaveFailed, .storedChatMemoryToolRejected,
        .storedChatProfileToolRejected, .storedChatNewChat, .storedChatMcpDenied, .storedChatMcpToolError,
        .storedChatMcpLocalLimit, .storedChatMcpLimit, .storedContextIncompleteHistory, .storedContextTooLarge,
        .storedReferencePrepareFailed, .storedReferenceRevoked, .storedReferenceBusy, .storedReferenceLifecycle,
        .storedInteractionNoSnapshot, .storedInteractionStale, .storedInteractionUnavailable,
        .storedInteractionInvalid, .storedInteractionUnsafe, .storedInteractionApprovalRequired,
        .storedInteractionExpired, .storedInteractionBusy, .storedInteractionFailed, .storedInteractionTimeout,
        .storedResearchInvalidCommand, .storedResearchInvalidJSON, .storedResearchUnsupported,
        .storedResearchUnknownLink, .storedResearchCommandTooLarge, .storedResearchNoPage,
        .storedResearchUnsafeNavigation, .storedResearchPageChanged, .storedResearchNavigationFailed,
        .storedResearchNavigationTimeout, .storedResearchReadTimeout, .storedResearchDeadline,
        .storedResearchModelConfiguration, .storedResearchModelRedirect, .storedResearchModelHTTPInvalid,
        .storedResearchInvalidResponse, .storedResearchIncompleteResponse, .storedResearchResponseTooLarge,
        .storedResearchBackpressure, .storedResearchModelTimeout, .storedResearchConnectionFailed,
        .storedResearchReferenceRevoked, .storedResearchCancelled, .storedResearchFailed, .storedResearchStepLimit,
        .storedBrowserStart, .storedBrowserInteractionIntro, .storedBrowserInvalidInput, .storedBrowserStopped,
        .storedBrowserResearching, .storedBrowserResearchStoppedUnconfirmed, .storedBrowserAnswerDelivered,
        .storedBrowserResearchEnded, .storedBrowserResearchUnfinished, .storedBrowserNeedsModel,
        .storedBrowserLearnStale, .storedBrowserLearnNotSaved, .storedBrowserJudgedDoneNoDraft,
        .storedBrowserJudgedDoneDraft, .storedBrowserJudgedPartial, .storedBrowserJudgedNotPossible,
        .storedBrowserJudgedUnknown, .storedBrowserLearnUnfinished, .storedBrowserReplaying,
        .storedBrowserReplayTimeout, .storedBrowserReplayDone, .storedBrowserReplayNotSaved,
        .storedBrowserReplayUnconfirmed, .storedBrowserReplayEnded, .storedBrowserReplayStopped,
        .storedBrowserReplayUnavailable, .storedBrowserAwaitApproval, .storedBrowserReadingControls,
        .storedBrowserControlsUpdated, .storedBrowserModelProposing, .storedBrowserProposalTimeout,
        .storedBrowserRunning, .storedBrowserActionSent, .storedBrowserRejected, .storedBrowserCancelled,
        .storedBrowserReloaded, .storedBrowserLoading, .storedBrowserRequestUnfinished,
        .storedBrowserSitePreferenceSaved, .storedBrowserOutsideScope, .storedBrowserNoDownload,
        .storedBrowserLoadedManual, .storedBrowserLoaded, .storedBrowserLoadFailed, .storedBrowserProcessStopped,
        .storedBrowserLoadIncomplete, .storedBrowserLoadedUnread, .storedBrowserReadIncomplete,
        .storedBrowserPostLoadReadIncomplete, .storedBrowserLoadIncompleteCheck, .storedBrowserReadTooLarge,
    ]

    /// Closed tails a store appends to another stored message, e.g. 「…草稿已保留。」.
    static let storedSuffixes: [AppText] = [
        .storedSuffixDraftKept, .storedSuffixToolResultsKept, .storedSuffixReplayNoSkip,
    ]

    private static let storedPatterns: [(AppText, (StoredValues) -> AppText?)] = [
        (.learningRemembered(value: ""), { .learningRemembered(value: $0.text(1)) }),
        (.learningUpdated(value: ""), { .learningUpdated(value: $0.text(1)) }),
        (.learningPendingProcedure(value: ""), { .learningPendingProcedure(value: $0.text(1)) }),
        (.storedChatContextWindow(retained: 0, omitted: 0), { values in
            guard let retained = values.count(1), let omitted = values.count(2) else { return nil }
            return .storedChatContextWindow(retained: retained, omitted: omitted)
        }),
        (.storedChatMemorySavedReplyTimeout(seconds: 0), { values in
            guard let seconds = values.count(1) else { return nil }
            return .storedChatMemorySavedReplyTimeout(seconds: seconds)
        }),
        (.storedChatWaitTimeout(seconds: 0), { values in
            guard let seconds = values.count(1) else { return nil }
            return .storedChatWaitTimeout(seconds: seconds)
        }),
        (.storedChatProfileSavedReplyTimeout(seconds: 0), { values in
            guard let seconds = values.count(1) else { return nil }
            return .storedChatProfileSavedReplyTimeout(seconds: seconds)
        }),
        (.storedChatMcpActivity(tried: 0, received: 0, failed: 0), { values in
            guard let tried = values.count(1), let received = values.count(2), let failed = values.count(3) else { return nil }
            return .storedChatMcpActivity(tried: tried, received: received, failed: failed)
        }),
        (.storedResearchModelHTTP(code: 0), { values in
            guard let code = values.count(1) else { return nil }
            return .storedResearchModelHTTP(code: code)
        }),
    ]
}
