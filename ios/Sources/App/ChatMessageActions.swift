import Foundation

/// Android ChatCopy.branchTitle: the source title's first line, shortened so
/// that with the localized suffix (" · 分支") it stays within 24 characters,
/// and always a single-line title the archive accepts.
enum ChatBranchTitle {
    static let maximumCharacters = 24
    /// ConversationArchive.maximumTitleBytes.
    static let maximumBytes = 512

    static func make(base: String, suffix: String, fallback: String) -> String {
        let room = max(0, maximumCharacters - suffix.count)
        for candidate in [base, fallback] {
            var kept = String(firstLine(candidate).prefix(room)).trimmingCharacters(in: .whitespaces)
            while !kept.isEmpty && (kept + suffix).utf8.count > maximumBytes { kept.removeLast() }
            kept = kept.trimmingCharacters(in: .whitespaces)
            if !kept.isEmpty { return kept + suffix }
        }
        return suffix.trimmingCharacters(in: .whitespaces)
    }

    /// The first line with text, without control or format characters.
    private static func firstLine(_ text: String) -> String {
        let removed = CharacterSet.controlCharacters
        for line in text.components(separatedBy: .newlines) {
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: line.unicodeScalars.filter { !removed.contains($0) })
            let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
            if !cleaned.isEmpty { return cleaned }
        }
        return ""
    }
}

#if os(iOS)
import AssistantPersistence
import SwiftUI
import UIKit

/// Copy for the long-press menu, quotes and branching, from the Android
/// store build (play.2 strings_chat.xml), in the chosen interface language.
struct ChatMessageMenuText {
    let localizer: AppLocalizer

    var copy: String { localizer.text(.chatMessageCopy) }
    var copied: String { localizer.text(.chatMessageCopied) }
    var quote: String { localizer.text(.chatMessageQuote) }
    var quoteFailed: String { localizer.text(.chatMessageQuoteFailed) }
    var removeQuote: String { localizer.text(.chatQuoteRemove) }
    var selectText: String { localizer.text(.chatMessageSelectText) }
    var selectHint: String { localizer.text(.chatMessageSelectHint) }
    var selectDone: String { localizer.text(.chatMessageSelectDone) }
    var branch: String { localizer.text(.chatBranch) }
    var askAgain: String { localizer.text(.chatBranchRetry) }
    var titleSuffix: String { localizer.text(.chatBranchTitleSuffix) }

    /// How VoiceOver reads a quote: 引用渥屋助理:… or 引用你的話:….
    func quoting(_ quote: ConversationQuote.Quote) -> String {
        localizer.text(quote.source == .assistant ? .chatQuotingAssistant(text: quote.text) : .chatQuotingYou(text: quote.text))
    }

    /// The toast after 從這裡分支 or 從這裡重新問; nil when the screen already says it.
    func toast(for outcome: ChatBranchOutcome) -> String? {
        switch outcome {
        case .created: return localizer.text(.chatBranchDone)
        case .needsReattach: return localizer.text(.chatBranchAttachmentsReadd)
        case .startedOver: return nil
        case .failed: return localizer.text(.chatBranchFailed)
        }
    }
}

enum ChatMessageAction {
    case copy, quote, selectText, branch, askAgain
}

/// The long-press menu on one message (Android MessageMenu): copy, quote and
/// select text, then 從這裡分支 on a finished reply or 從這裡重新問 on your
/// own message, each only while it works. The same entries are VoiceOver
/// actions.
struct ChatMessageMenu: ViewModifier {
    let entry: ChatEntry
    let targets: ChatMessageActionTargets
    let text: ChatMessageMenuText
    let perform: (ChatMessageAction) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
            .contextMenu { items }
            .accessibilityActions { items }
    }

    @ViewBuilder private var items: some View {
        item(.copy, text.copy, symbol: "doc.on.doc", id: "copy")
        if targets.saved.contains(entry.id) { item(.quote, text.quote, symbol: "text.quote", id: "quote") }
        item(.selectText, text.selectText, symbol: "selection.pin.in.out", id: "selectText")
        if targets.replies.contains(entry.id) { item(.branch, text.branch, symbol: "arrow.triangle.branch", id: "branch") }
        if targets.questions.contains(entry.id) { item(.askAgain, text.askAgain, symbol: "arrow.triangle.branch", id: "askAgain") }
    }

    private func item(_ action: ChatMessageAction, _ title: String, symbol: String, id: String) -> some View {
        Button { perform(action) } label: { Label(title, systemImage: symbol) }
            .accessibilityIdentifier("chat.messageMenu." + id)
    }
}

/// Android QuoteChip: the quote waiting above the input bar, an accent bar,
/// at most two lines, and × to remove it.
struct ChatQuoteChip: View {
    let quote: ConversationQuote.Quote
    let colors: ChatAttachmentColors
    let text: ChatMessageMenuText
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(colors.accent).frame(width: 3, height: 30)
            Text(verbatim: quote.text)
                .font(.caption).foregroundStyle(colors.secondaryInk)
                .lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
                .accessibilityLabel(text.quoting(quote))
                .accessibilityIdentifier("chat.quote.text")
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.secondaryInk)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRemove)
            .accessibilityLabel(text.removeQuote)
            .accessibilityIdentifier("chat.quote.remove")
        }
        .padding(.leading, 12).padding(.vertical, 6)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.hair, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.quote")
    }
}

/// Android SentQuote: what your message quoted, a faint block above it, at
/// most two lines.
struct ChatSentQuote: View {
    let quote: ConversationQuote.Quote
    let colors: ChatAttachmentColors
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(colors.secondaryInk.opacity(0.6)).frame(width: 2, height: 16)
            Text(verbatim: quote.text)
                .font(.caption).foregroundStyle(colors.secondaryInk)
                .lineLimit(2).truncationMode(.tail)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(colors.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// What 選取文字 opened: the message's plain text.
struct ChatSelectTextTarget: Identifiable {
    let id = UUID()
    let text: String
}

/// Android switches the message to the system's text selection; iOS Text
/// cannot select part of itself, so the plain text opens selectable here.
struct ChatSelectTextSheet: View {
    let target: ChatSelectTextTarget
    let text: ChatMessageMenuText
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: text.selectHint)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, 8)
                ChatSelectableText(text: target.text)
                    .padding(.horizontal, 12)
            }
            .navigationTitle(text.selectText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text.selectDone) { dismiss() }
                        .accessibilityIdentifier("chat.selectText.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("chat.selectText")
    }
}

private struct ChatSelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        view.accessibilityIdentifier = "chat.selectText.body"
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

/// A short notice over the transcript, like an Android toast.
struct ChatToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct ChatToastView: View {
    let toast: ChatToast

    var body: some View {
        Text(verbatim: toast.text)
            .font(.callout).foregroundStyle(Color(uiColor: .systemBackground))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            // Inverted, like a system toast, in light and dark appearance.
            .background(Color(uiColor: .label).opacity(0.85), in: Capsule())
            .padding(.horizontal, 24)
            // Like a toast, it never takes a touch meant for the message under it.
            .allowsHitTesting(false)
            .accessibilityIdentifier("chat.toast")
    }
}
#endif
