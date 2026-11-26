#if WOOWTECHBOT
import SwiftUI

enum BotChatSheet: String, Identifiable { case edit, search, files, notifications; var id: String { rawValue } }

struct BotConversationSearch: View {
    @ObservedObject var chat: ChatSession
    let localizer: AppLocalizer
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    var body: some View {
        NavigationStack {
            List {
                ForEach(chat.entries.filter { !query.isEmpty && $0.content.localizedCaseInsensitiveContains(query) }) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.role == "user" ? t("你", "You") : t("助理", "Assistant")).font(.caption).foregroundStyle(.secondary)
                        Text(entry.content).textSelection(.enabled)
                    }
                }
            }
            .searchable(text: $query, prompt: t("搜尋這段對話", "Search this conversation"))
            .navigationTitle(t("在對話中尋找", "Find in conversation")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("完成", "Done")) { dismiss() } } }
        }
    }
}

struct BotConversationFiles: View {
    @ObservedObject var chat: ChatSession
    let localizer: AppLocalizer
    @State private var preview: ChatAttachmentPreviewTarget?
    @State private var delivery: ChatCreatedFileDelivery?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var files: [ChatCreatedFile] { chat.entries.flatMap { chat.createdFiles[$0.id] ?? [] } }
    private var attachments: [ChatAttachmentItem] {
        var seen = Set<UUID>()
        return (chat.pendingAttachments + chat.entries.flatMap(\.attachments)).filter { seen.insert($0.id).inserted }
    }
    var body: some View {
        NavigationStack {
            List {
                if files.isEmpty && attachments.isEmpty { Text(t("這段對話沒有檔案", "No files in this conversation")) }
                ForEach(attachments) { file in
                    Button {
                        let url = chat.attachmentStore.url(for: file)
                        if FileManager.default.isReadableFile(atPath: url.path) { preview = .init(url: url) }
                    } label: { Label(file.name, systemImage: "doc") }
                    .disabled(!chat.attachmentStore.exists(file))
                }
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 10) {
                        Button(file.name) { preview = .init(url: file.url) }.disabled(!chat.createdFileIsAvailable(file))
                        if chat.createdFileIsAvailable(file) {
                            HStack {
                                Button(t("存到檔案", "Save to Files")) { delivery = .save(file) }
                                Button(t("分享", "Share")) { delivery = .share(file) }
                            }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle(t("對話檔案", "Conversation files")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("完成", "Done")) { dismiss() } } }
            .sheet(item: $preview) { target in ChatAttachmentPreview(url: target.url, onDismiss: { preview = nil }) }
            .modifier(ChatCreatedFilePresentations(delivery: $delivery, finish: chat.finishCreatedFile))
        }
    }
}
#endif
