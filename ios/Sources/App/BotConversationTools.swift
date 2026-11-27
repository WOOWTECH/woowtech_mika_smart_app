#if WOOWTECHBOT
import SwiftUI

/// Pages that open over the chat: name and icon, find in conversation, files. Notifications are a bottom sheet instead.
enum BotChatPage: String, Identifiable { case edit, search, files; var id: String { rawValue } }
enum BotChatSheet: String, Identifiable { case notifications; var id: String { rawValue } }

/// The chat header's "…" popover.
enum BotChatMenu: BotPopoverID {
    case more
    var anchorID: String { "chat.more" }
    var placement: BotPopoverPlacement { .belowTrailing }
}

/// Android `BotUiFind`: a search pill, the match count, and every matching message on its own card.
struct BotConversationSearch: View {
    @ObservedObject var chat: ChatSession
    let localizer: AppLocalizer
    let close: () -> Void
    @State private var query = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var matches: [ChatEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? [] : chat.entries.filter { $0.content.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        BotPage(title: t("對話中尋找", "Find in conversation"), closeLabel: t("關閉", "Close"), close: close) {
        } content: {
            BotSearchPill(text: $query, placeholder: t("對話中尋找", "Find in conversation"), clearLabel: t("關閉", "Close"),
                          identifier: "bot.find.search", focused: $focused)
                .padding(.horizontal, 16).padding(.vertical, 8)
            Text(localizer.language == .english ? "\(matches.count) matches" : "\(matches.count) 個符合結果")
                .scaledFont(size: 12).foregroundStyle(palette.secondaryInk).padding(.horizontal, 24).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("bot.find.count")
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(matches) { entry in
                        Text(entry.content).scaledFont(size: 15).lineSpacing(5).foregroundStyle(palette.ink).textSelection(.enabled)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(16)
            }.scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focused = true }
    }
}

/// Android `BotUiFiles`: the conversation's files, one card per file. A generated file can also be saved or shared.
struct BotConversationFiles: View {
    @ObservedObject var chat: ChatSession
    let localizer: AppLocalizer
    let close: () -> Void
    @State private var preview: ChatAttachmentPreviewTarget?
    @State private var delivery: ChatCreatedFileDelivery?
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var files: [ChatCreatedFile] { chat.entries.flatMap { chat.createdFiles[$0.id] ?? [] } }
    private var attachments: [ChatAttachmentItem] {
        var seen = Set<UUID>()
        return (chat.pendingAttachments + chat.entries.flatMap(\.attachments)).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        BotPage(title: t("檔案", "Files"), closeLabel: t("關閉", "Close"), close: close) {
        } content: {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if files.isEmpty && attachments.isEmpty {
                        Text(t("這段對話尚無匯出檔案。", "No exported files in this conversation yet."))
                            .scaledFont(size: 14).foregroundStyle(palette.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("bot.files.empty")
                    }
                    ForEach(attachments) { file in
                        Button {
                            let url = chat.attachmentStore.url(for: file)
                            if FileManager.default.isReadableFile(atPath: url.path) { preview = .init(url: url) }
                        } label: { fileRow(file.name, palette) }
                        .buttonStyle(.plain).disabled(!chat.attachmentStore.exists(file))
                    }
                    ForEach(files) { file in
                        VStack(spacing: 0) {
                            Button { preview = .init(url: file.url) } label: { fileRow(file.name, palette) }
                                .buttonStyle(.plain).disabled(!chat.createdFileIsAvailable(file))
                            if chat.createdFileIsAvailable(file) {
                                HStack(spacing: 8) {
                                    BotPillButton(title: t("存到檔案", "Save to Files"), fill: true, look: .app,
                                                  identifier: "bot.files.save") { delivery = .save(file) }
                                    BotPillButton(title: t("分享", "Share"), fill: true, look: .app,
                                                  identifier: "bot.files.share") { delivery = .share(file) }
                                }.padding(.horizontal, 12).padding(.bottom, 12)
                            }
                        }.background(palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(16)
            }
        }
        .sheet(item: $preview) { target in ChatAttachmentPreview(url: target.url, onDismiss: { preview = nil }) }
        .modifier(ChatCreatedFilePresentations(delivery: $delivery, finish: chat.finishCreatedFile))
    }

    private func fileRow(_ name: String, _ palette: MikaVisualPalette) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 17, weight: .regular)).foregroundStyle(palette.secondaryInk).frame(width: 20, height: 20)
            Text(name).scaledFont(size: 15).foregroundStyle(palette.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
    }
}
#endif
