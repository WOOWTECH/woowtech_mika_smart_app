import Foundation

/// Android-compatible message quote serialization. Pass the assistant's
/// displayed plain text, not Markdown source, when quoting an assistant reply.
public enum ConversationQuote {
    public enum Source: String, Equatable, Sendable {
        case assistant = "> [Quoting your earlier reply]"
        case user = "> [Quoting my earlier message]"
    }
    public struct Quote: Equatable, Sendable {
        public let source: Source
        public let text: String
        public init(source: Source, text: String) { self.source = source; self.text = text }
    }
    public struct Parsed: Equatable, Sendable {
        public let quote: Quote?
        public let words: String
    }
    public static let maximumUTF16Units = 1000

    /// Android measures UTF-16 units. Do not cut a surrogate pair in half.
    public static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count > maximumUTF16Units else { return trimmed }
        var result = String.UnicodeScalarView()
        var units = 0
        for scalar in trimmed.unicodeScalars {
            let length = scalar.value > 0xffff ? 2 : 1
            guard units + length <= maximumUTF16Units else { break }
            result.append(scalar); units += length
        }
        return String(result).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    public static func compose(_ quote: Quote?, words: String) -> String {
        guard let quote else { return words }
        let body = clip(quote.text)
        guard !body.isEmpty else { return words }
        let lines = normalizedLines(body).map { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ">" : "> " + line
        }
        let block = ([quote.source.rawValue] + lines).joined(separator: "\n")
        return words.isEmpty ? block : block + "\n\n" + words
    }

    /// Text-only sends cannot consist solely of a quote. Attachment sends have
    /// their own eligibility checks and may use compose directly.
    public static func textForSend(_ quote: Quote?, words: String) -> String? {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : compose(quote, words: trimmed)
    }

    public static func parse(_ text: String) -> Parsed {
        let lines = normalizedLines(text)
        guard let first = lines.first,
              let source = Source(rawValue: first.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return Parsed(quote: nil, words: text)
        }
        var index = 1
        var quoted: [String] = []
        while index < lines.count && lines[index].hasPrefix(">") {
            var line = String(lines[index].dropFirst())
            if line.hasPrefix(" ") { line.removeFirst() }
            quoted.append(line); index += 1
        }
        return Parsed(quote: Quote(source: source, text: quoted.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)),
            words: lines.dropFirst(index).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}

public enum ConversationBranchError: Error, Equatable {
    case blocked, unfinishedTurn, staleSource, invalidSelection, invalidTarget
}

/// A prepared, in-memory branch. The host must re-check its live task and
/// unfinished/unsaved state when applying, and persist the returned snapshot
/// atomically before switching conversations.
public struct ConversationBranchPlan {
    public let source: ArchivedConversation
    public let parentTurn: Int
    public let branch: ArchivedConversation
    public let title: String

    public static func prepare(in archive: ConversationArchive, source: ArchivedConversation,
                               assistantID: UUID, targetID: UUID, title: String, at: Date,
                               isBusy: Bool, hasUnfinishedOrUnsavedTurn: Bool) throws -> Self {
        guard !isBusy else { throw ConversationBranchError.blocked }
        guard !hasUnfinishedOrUnsavedTurn else { throw ConversationBranchError.unfinishedTurn }
        guard archive.conversations.first(where: { $0.id == source.id }) == source else {
            throw ConversationBranchError.staleSource
        }
        guard let index = source.turns.firstIndex(where: { $0.assistantID == assistantID }) else {
            throw ConversationBranchError.invalidSelection
        }
        guard targetID != source.id, !archive.conversations.contains(where: { $0.id == targetID }),
              ConversationArchive.normalizedTitle(title) == title else { throw ConversationBranchError.invalidTarget }
        // 沒有完成 and 已停止。 turns stay what they were, like the Play build's copy.
        let copied = try source.turns.prefix(index + 1).map {
            try ArchivedConversationTurn(userText: $0.userText, assistantText: $0.assistantText, pdf: $0.pdf,
                                         outcome: $0.outcome)
        }
        let branch = try ArchivedConversation(id: targetID, destination: source.destination, updatedAt: at, turns: copied)
        let plan = Self(source: source, parentTurn: index, branch: branch, title: title)
        _ = try plan.applying(to: archive, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        return plan
    }

    public func applying(to archive: ConversationArchive, isBusy: Bool,
                         hasUnfinishedOrUnsavedTurn: Bool) throws -> ConversationArchive {
        guard !isBusy else { throw ConversationBranchError.blocked }
        guard !hasUnfinishedOrUnsavedTurn else { throw ConversationBranchError.unfinishedTurn }
        guard archive.conversations.first(where: { $0.id == source.id }) == source else {
            throw ConversationBranchError.staleSource
        }
        guard !archive.conversations.contains(where: { $0.id == branch.id }) else {
            throw ConversationBranchError.invalidTarget
        }
        var next = archive
        try next.insertBranch(self)
        return next
    }
}
