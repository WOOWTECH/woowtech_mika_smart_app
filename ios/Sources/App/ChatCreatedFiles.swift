import AssistantBrowser
import Foundation

/// A file the assistant made in a reply (file_create), waiting in the app as a
/// card under that reply until the person saves, shares or removes it.
struct ChatCreatedFile: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case ready
        /// Delivered or dismissed: the app's copy is gone.
        case saved, shared, removed
        /// Deleted by the app, after a day or by the system.
        case missing
    }
    let id: UUID
    let name: String
    /// pdf, docx, xlsx, pptx or zip.
    let format: String
    let byteCount: Int64
    let url: URL
    var state: State = .ready
}

/// The App's file_create, supplied by the root view with the device's writers
/// and PDF renderer (ChatFileCreation); hosted tests and the Mac checks have
/// none, and then chat offers no files.
struct ChatFileTool: Sendable {
    static let name = "file_create"
    /// The offer in an ordinary chat, and inside a step that already runs commands.
    let offer: String
    let inStep: String
    let accepts: @Sendable (String) -> Bool
    /// What the model reads when a request already made as many files as it may.
    let limitResult: String
    /// Makes the file. `earlier` holds this conversation's files by name, for a
    /// ZIP; `language` is the interface's, for a PDF's Chinese glyphs.
    let make: @Sendable (_ command: String, _ earlier: [String: URL], _ language: String) async -> ChatFileToolOutcome
}

enum ChatFileToolOutcome: Sendable {
    case created(ChatCreatedFile, result: String)
    case failed(result: String)
}

enum ChatCreatedFileLimits {
    static let maximumPerRequest = 8
    /// All created files waiting in the app, like the export cache.
    static let maximumStoredBytes: Int64 = 100 * 1_048_576
    /// A share sheet's receiver may still be reading when it reports the share done.
    static let deleteAfterShare: TimeInterval = 30
}

/// Created files in their own PendingFileFolder: each item folder holds the
/// file and, once its reply is in the conversation, a note naming that reply,
/// so the card comes back when the conversation is opened again after the app
/// restarts. A file without a reply is a request that never finished; it is
/// deleted at the next start, and every file a day after it was made.
final class ChatCreatedFileStore: @unchecked Sendable {
    static let replyNote = ".reply"
    let folder: PendingFileFolder

    init(folder: PendingFileFolder) { self.folder = folder }

    static func live() -> ChatCreatedFileStore { ChatCreatedFileStore(folder: .live("CreatedFiles")) }

    /// At start: delete what expired or never reached a reply, then each remaining card by its reply.
    func load(now: Date = Date()) -> [UUID: [ChatCreatedFile]] {
        folder.purge(now: now)
        var cards: [UUID: [ChatCreatedFile]] = [:]
        for item in folder.items().sorted(by: { $0.modified < $1.modified }) {
            let note = item.folder.appendingPathComponent(Self.replyNote)
            guard let text = try? String(contentsOf: note, encoding: .utf8), let reply = UUID(uuidString: text),
                  let file = folder.files(in: item.folder).first, let created = Self.card(item.id, file) else {
                folder.remove(item.id)
                continue
            }
            cards[reply, default: []].append(created)
        }
        return cards
    }

    /// Saves a new file, refused when the folder would pass its limit.
    func save(_ data: Data, name: String, format: String) throws -> ChatCreatedFile {
        guard folder.storedBytes() + Int64(data.count) <= ChatCreatedFileLimits.maximumStoredBytes else {
            throw ChatCreatedFileError.storageFull
        }
        let id = UUID()
        let url = try folder.write(data, named: name, id: id)
        return ChatCreatedFile(id: id, name: name, format: format, byteCount: Int64(data.count), url: url)
    }

    /// The reply the card belongs to, written once that reply is in the conversation.
    func attach(_ file: ChatCreatedFile, to reply: UUID) {
        let note = file.url.deletingLastPathComponent().appendingPathComponent(Self.replyNote)
        try? Data(reply.uuidString.utf8).write(to: note, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ file: ChatCreatedFile) { folder.remove(file.id) }

    func exists(_ file: ChatCreatedFile) -> Bool { FileManager.default.isReadableFile(atPath: file.url.path) }

    private static func card(_ id: UUID, _ file: URL) -> ChatCreatedFile? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return ChatCreatedFile(id: id, name: file.lastPathComponent, format: file.pathExtension.lowercased(),
                               byteCount: Int64(size), url: file)
    }
}

enum ChatCreatedFileError: Error, Equatable { case storageFull }
