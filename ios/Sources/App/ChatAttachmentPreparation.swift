import AssistantModels
import Foundation

/// What one prompt's attachments become for the model: content it can read,
/// plus short notes for anything it could not, so nothing is dropped silently.
struct ChatAttachmentPrepared: Sendable {
    let attachments: [ModelAttachment]
    /// Appended to the prompt text for this request only.
    let notes: [String]
    /// Images left out because the model is not marked as able to see them.
    let unseenImages: Int
}

enum ChatAttachmentPreparation {
    /// Room left for attachment text after the prompt and reference context,
    /// inside the same 64 KiB window the chat already uses. Never below 8 KiB,
    /// so a long prompt still gets a useful excerpt of each file.
    static func textBudget(promptBytes: Int, contextBytes: Int) -> Int {
        max(8 * 1024, 64 * 1024 - promptBytes - contextBytes)
    }

    /// Reads the app's own copies off the main actor. The order is the order shown.
    static func prepare(_ items: [ChatAttachmentItem], store: ChatAttachmentStore,
                        vision: ModelVisionCapability, textBudgetBytes: Int) -> ChatAttachmentPrepared {
        let textual = items.filter { $0.kind == .file }.count
        let note = "\n（內容過長，只附上前面一部分）"
        // Each file's share of the budget, inside the per-attachment limit.
        let perFile = textual == 0 ? 0
            : max(2 * 1024, min(ModelAttachment.maximumTextBytes - note.utf8.count, textBudgetBytes / textual))
        var attachments: [ModelAttachment] = []
        var notes: [String] = []
        var unseen = 0
        for item in items {
            let url = store.url(for: item)
            guard FileManager.default.fileExists(atPath: url.path) else {
                notes.append(item.name + ":" + "這個附件已經不在了"); continue
            }
            let result = ChatAttachmentReader.read(fileURL: url, kind: item.kind, contentType: item.contentType,
                                                   textByteLimit: item.kind == .photo ? 0 : perFile)
            switch result.content {
            case .image(let jpeg, _, _):
                guard vision == .supported else {
                    unseen += 1
                    notes.append(item.name + ":" + "這個模型不能看圖，沒有附上圖片內容")
                    continue
                }
                if let image = try? ModelAttachment.image(data: jpeg, mimeType: "image/jpeg", label: item.name) {
                    attachments.append(image)
                } else {
                    notes.append(item.name + ":" + "這張圖片沒能讀取")
                }
            case .text(let text, let truncated):
                let body = truncated ? text + note : text
                if !body.isEmpty, let file = try? ModelAttachment.text(utf8: Data(body.utf8), label: item.name) {
                    attachments.append(file)
                } else {
                    notes.append(item.name + ":" + "這個檔案沒有可讀取的內容")
                }
            case .unreadable(let reason):
                notes.append(item.name + ":" + reason)
            }
        }
        return ChatAttachmentPrepared(attachments: attachments, notes: notes, unseenImages: unseen)
    }

    /// The prompt text sent with this request: the archived text plus the notes.
    static func promptText(_ archived: String, notes: [String]) -> String {
        guard !notes.isEmpty else { return archived }
        return archived + "\n" + notes.map { "（" + $0 + "）" }.joined(separator: "\n")
    }
}
