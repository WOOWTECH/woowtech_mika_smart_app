import AssistantModels
import Foundation
import UniformTypeIdentifiers

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

    /// The note for a picture the model is not marked as able to see.
    static let unseenImageReason = "這個模型不能看圖，沒有附上圖片內容"

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
                    notes.append(item.name + ":" + unseenImageReason)
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

/// Android's vision model reading a screenshot, for a chat picture: when the
/// main model cannot see images, the vision role's own model (agreed to)
/// looks at the attached pictures first and describes them, and the main
/// model reads that description. Without it the "cannot see" note stays.
enum ChatVisionHandoff {
    static let instruction = """
        You are the vision model of an assistant whose main model cannot see images. Describe every attached \
        picture for that main model: all readable text exactly as written, numbers, objects, people (never who \
        they are), the layout, and whatever matters for the user's question. Do not answer the question \
        yourself. Write in the language of the user's question.
        """

    /// A few paragraphs are enough. A bounded request also passes a provider
    /// that checks the account's credit against the output asked for
    /// (OpenRouter refuses an unbounded one when the credit is short), and
    /// leaves a reasoning model room to think first.
    static let maximumOutputTokens = 4_096

    /// The pictures' description, or nil when none of the items is a picture.
    /// A picture counts however it was attached (相簿, 相機 or 檔案).
    /// Throws what the vision model's call threw, or that it said nothing.
    static func describe(_ items: [ChatAttachmentItem], store: ChatAttachmentStore, question: String,
                         client: any ChatModelClient, configuration: ModelConfiguration, key: String) async throws -> String? {
        let pictures = items.filter { item in
            item.kind == .photo || item.contentType.flatMap(UTType.init)?.conforms(to: .image) ?? true
        }
        guard !pictures.isEmpty else { return nil }
        let prepared = await Task.detached(priority: .userInitiated) {
            ChatAttachmentPreparation.prepare(pictures, store: store, vision: .supported, textBudgetBytes: 0)
        }.value
        let images = prepared.attachments.filter(\.isImage)
        guard !images.isEmpty else { return nil }
        let text = instruction + "\n\nUser's question: " + String(question.prefix(2_000))
        let reply = try await client.complete(messages: [ModelMessage(userText: text, attachments: images)],
                                              configuration: configuration.withMaxOutputTokens(maximumOutputTokens),
                                              apiKey: key)
        let described = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !described.isEmpty else { throw ChatVisionHandoffError.noDescription }
        return String(described.prefix(8_000))
    }

    /// The main request's notes: the description in place of each picture's
    /// "cannot see" note. It says the main model only has these words, so a
    /// later "look again" is answered from them, not as if it saw the picture
    /// (the conversation keeps this text, not the picture).
    static func notes(_ notes: [String], description: String) -> [String] {
        notes.filter { !$0.hasSuffix(":" + ChatAttachmentPreparation.unseenImageReason) }
            + ["看圖模型對附圖的說明（你沒有直接看到圖片，只有這份說明。之後被問到圖片時，以這份說明回答；"
               + "被要求再看一次時，要說明你只能根據這份說明回答，需要更多細節請使用者重新附上圖片）：\n" + description]
    }
}

enum ChatVisionHandoffError: Error { case noDescription }

/// Why the vision model did not describe this turn's pictures: its model, and
/// the model call's failure when the chat has words for it.
struct ChatVisionFailure: Equatable {
    let model: String
    let failure: ChatModelFailure?

    init(model: String, error: Error) {
        self.model = model
        failure = ChatModelFailure(error)
    }
}
