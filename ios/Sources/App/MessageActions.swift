import AssistantPersistence
import Foundation

/// Captured when presenting a menu. All mutating actions revalidate through
/// ChatSession; the captured archive row must never be replaced with a newer one.
@MainActor struct MessageActions {
    let conversationID: UUID
    let entry: ChatEntry
    let source: ArchivedConversation?

    static func capture(entry: ChatEntry, in session: ChatSession) -> Self? {
        guard let id = UUID(uuidString: session.conversationID),
              session.entries.contains(where: { $0.id == entry.id && $0.role == entry.role
                  && $0.content == entry.content && $0.pdf == entry.pdf }),
              ["user", "assistant"].contains(entry.role), !entry.content.isEmpty else { return nil }
        let source = session.archive?.state.conversations.first { $0.id == id }
        return Self(conversationID: id, entry: entry, source: source)
    }

    private func isVisible(in session: ChatSession) -> Bool {
        session.isCurrentConversation(id: conversationID) && session.entries.contains {
            $0.id == entry.id && $0.role == entry.role && $0.content == entry.content && $0.pdf == entry.pdf
        }
    }

    var canQuote: Bool {
        guard let source else { return false }
        return source.turns.contains { $0.userID == entry.id || $0.assistantID == entry.id }
    }
    func canBranch(in session: ChatSession) -> Bool {
        guard let source, entry.role == "assistant", source.turns.contains(where: { $0.assistantID == entry.id }) else { return false }
        return isVisible(in: session) && session.archive?.available == true && !session.isSubmitting
            && session.replyPreview == nil && session.archiveNotice == nil && !session.canRetryArchiveSave
            && session.draft.isEmpty && session.pendingQuote == nil && session.pdfAttachment == nil
    }

    /// The clipboard sink runs only on an explicit action and only if the same
    /// message is still displayed. The caller supplies assistant display text.
    @discardableResult func copy(in session: ChatSession, assistantPlainText: (String) -> String,
                                 write: (String) -> Void) -> Bool {
        guard isVisible(in: session) else { return false }
        let text = entry.role == "assistant" ? assistantPlainText(entry.content) : ConversationQuote.parse(entry.content).words
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        write(text); return true
    }

    @discardableResult func quote(in session: ChatSession) -> Bool {
        guard let source, isVisible(in: session), let archive = session.archive else { return false }
        archive.reload()
        guard archive.available, archive.state.conversations.first(where: { $0.id == source.id }) == source else { return false }
        return session.selectQuote(messageID: entry.id, expectedContent: entry.content, in: conversationID)
    }

    @discardableResult func branch(in session: ChatSession, suffix: String) -> Bool {
        guard canBranch(in: session), let source else { return false }
        // Keep archive titles valid even when the original first message has
        // line breaks, controls or unusually large multi-scalar characters.
        let sanitized = source.title.unicodeScalars.map {
            CharacterSet.controlCharacters.union(.newlines).contains($0) ? " " : String($0)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        var base = String(sanitized.prefix(24))
        while !base.isEmpty && ConversationArchive.normalizedTitle(base + suffix) == nil { base.removeLast() }
        let title = (base.isEmpty ? "Chat" : base) + suffix
        do {
            let plan = try session.prepareBranch(source: source, assistantID: entry.id, title: title)
            _ = try session.commitBranch(plan)
            return true
        } catch { return false }
    }
}

/// Presentation only: a serialized marker can be typed by anyone and must
/// never be used as evidence about authorship, memory, or tool authorization.
struct MessageUserPresentation {
    let quote: ConversationQuote.Quote?
    let words: String
    init(_ raw: String) {
        let parsed = ConversationQuote.parse(raw)
        quote = parsed.quote
        words = parsed.words
    }
}
