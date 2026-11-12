import AssistantPersistence
import Foundation
import UniformTypeIdentifiers

enum ChatAttachmentKind: String, Codable, Sendable { case photo, file }

/// A stored attachment: the app's own copy, never the user's original URL.
struct ChatAttachmentItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: ChatAttachmentKind
    let name: String
    let byteCount: Int64
    /// Relative to `ChatAttachmentStore.root`, so a restored container still resolves it.
    let relativePath: String
    let contentType: String?
    /// The photo library asset it came from, so tapping that photo again removes it. Not archived.
    var sourceKey: String? = nil
}

/// One picked photo or file, already the app's own temporary copy, for ChatAttachmentStore.
struct ChatPickedFile: Sendable, Equatable {
    /// `tmp/ChatAttachmentImports/<UUID>/<name>`; the store deletes the `<UUID>` folder.
    let temporaryURL: URL
    let suggestedName: String
    /// A UTType identifier when known.
    let contentType: String?
    /// The Photos asset identifier, so one photo is not added twice; nil for documents.
    let dedupeKey: String?
}

/// The Android chat tray's limits (cap/sandbox/Attachments.kt, AttachmentMessage.kt).
enum ChatAttachmentLimits {
    static let maximumCount = 9
    static let maximumFileBytes: Int64 = 200 * 1024 * 1024
    static let minimumFreeBytes: Int64 = 500 * 1024 * 1024
    static let maximumConversationBytes: Int64 = 4 * 1024 * 1024 * 1024
}

enum ChatAttachmentNaming {
    /// Android decides photo or file by extension (AttachmentMessage.kt:49).
    static let photoExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "heif"]

    static func kind(forName name: String) -> ChatAttachmentKind {
        photoExtensions.contains((name as NSString).pathExtension.lowercased()) ? .photo : .file
    }

    /// No path separators or control characters, at most 120 characters, the extension kept.
    static func sanitized(_ raw: String, fallback: String) -> String {
        let cleaned = String(raw.unicodeScalars.filter { scalar in
            scalar != "/" && scalar != "\\" && !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.newlines.contains(scalar)
        }).trimmingCharacters(in: .whitespaces)
        let name = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? fallback : cleaned
        guard name.count > 120 else { return name }
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty || ext.count > 10 ? "" : "." + ext
        return String(name.prefix(120 - suffix.count)) + suffix
    }

    /// "a.txt", then "a (2).txt", like the Android inbox.
    static func uniqued(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for number in 2... {
            let candidate = base + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
            if !taken.contains(candidate) { return candidate }
        }
        return name
    }
}

/// The text the model sees for each attachment, in Android's format without the
/// sandbox path: iOS has no /workspace and the app container path is private.
enum ChatAttachmentLines {
    static let prefix = "附件:"

    static func line(for item: ChatAttachmentItem) -> String {
        prefix + item.name + "(" + ChatAttachmentFormat.byteString(item.byteCount) + ")"
    }

    static func compose(prompt: String, items: [ChatAttachmentItem]) -> String {
        guard !items.isEmpty else { return prompt }
        let lines = items.map(line(for:)).joined(separator: "\n")
        return prompt.isEmpty ? lines : prompt + "\n" + lines
    }

    /// The bubble shows only what the user typed; the attachment lines are drawn as cards.
    static func displayText(_ content: String, items: [ChatAttachmentItem]) -> String {
        guard !items.isEmpty else { return content }
        let lines = Set(items.map(line(for:)))
        var kept = content.components(separatedBy: "\n")
        while let last = kept.last, lines.contains(last) { kept.removeLast() }
        return kept.joined(separator: "\n")
    }

    /// Android's titles for a message that is only attachments (AttachmentMessage.kt:39-47).
    static func title(for items: [ChatAttachmentItem]) -> String {
        let photos = items.filter { $0.kind == .photo }
        let files = items.filter { $0.kind == .file }
        switch (photos.count, files.count) {
        case (1, 0): return "照片"
        case (let n, 0): return "\(n) 張照片"
        case (0, 1): return files[0].name
        case (0, let n): return "\(files[0].name) 等 \(n) 個檔案"
        default: return "照片和檔案"
        }
    }
}

/// What happened to one batch from a picker; shown above the input bar.
struct ChatAttachmentImportOutcome: Equatable, Sendable {
    var added: [ChatAttachmentItem] = []
    /// Names refused for size, space or an unreadable source.
    var refused: [String] = []
    /// How many were left out because the tray was already full.
    var overflow = 0
}

enum ChatAttachmentNotice: Equatable {
    case overLimit(Int)
    case refused([String])
    case cameraUnavailable
    /// Photos were sent as notes only because the model is not marked "能看圖".
    case imagesNotSeen(Int)
    /// A recent photo was tapped while nine are already waiting.
    case trayFull
    /// A sent attachment's file was removed from the app's folder.
    case missing
}

/// The app's private copies live in Application Support, outside iCloud backup,
/// one folder per conversation like Android's per-chat inbox.
struct ChatAttachmentStore: Sendable {
    let root: URL

    /// Same scope as the conversation archive ("personal", or an isolated UI test
    /// namespace), so test runs never touch or reveal the user's own files.
    @MainActor static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> ChatAttachmentStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let location = try? ConversationArchiveStore.location(arguments: arguments)
        let scope = location?.url.deletingLastPathComponent().lastPathComponent ?? "personal"
        let store = ChatAttachmentStore(root: base.appendingPathComponent("ChatAttachments/" + scope, isDirectory: true))
        if location?.reset == true { try? FileManager.default.removeItem(at: store.root) }
        return store
    }

    func url(for item: ChatAttachmentItem) -> URL {
        root.appendingPathComponent(item.relativePath, isDirectory: false)
    }

    func exists(_ item: ChatAttachmentItem) -> Bool {
        FileManager.default.fileExists(atPath: url(for: item).path)
    }

    /// Moves picked temporary copies into the conversation folder. Runs off the main actor.
    func importFiles(_ picked: [ChatPickedFile], conversationID: String,
                     existing: [ChatAttachmentItem]) -> ChatAttachmentImportOutcome {
        var outcome = ChatAttachmentImportOutcome()
        let manager = FileManager.default
        let folder = root.appendingPathComponent(conversationID, isDirectory: true)
        var taken = Set(existing.map(\.name))
        // A photo already waiting matches by its library asset; a file by name and size.
        var seen = Set(existing.compactMap { item in dedupeIdentity(name: item.name, size: item.byteCount) })
            .union(existing.compactMap(\.sourceKey))
        var room = ChatAttachmentLimits.maximumCount - existing.count
        var conversationBytes = folderBytes(folder)
        defer { for file in picked { try? manager.removeItem(at: file.temporaryURL.deletingLastPathComponent()) } }
        prepareRoot()
        for file in picked {
            let size = (try? file.temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
            let name = ChatAttachmentNaming.sanitized(file.suggestedName, fallback: file.contentType.flatMap(UTType.init)?
                .conforms(to: .image) == true ? "照片.jpg" : "檔案")
            if let key = file.dedupeKey ?? dedupeIdentity(name: name, size: size), seen.contains(key) { continue }
            guard room > 0 else { outcome.overflow += 1; continue }
            guard size >= 0, size <= ChatAttachmentLimits.maximumFileBytes, freeBytes() - size >= ChatAttachmentLimits.minimumFreeBytes,
                  conversationBytes + size <= ChatAttachmentLimits.maximumConversationBytes else {
                outcome.refused.append(name); continue
            }
            let unique = ChatAttachmentNaming.uniqued(name, taken: taken)
            let id = UUID()
            let relative = conversationID + "/" + id.uuidString + "/" + unique
            let destination = root.appendingPathComponent(relative, isDirectory: false)
            do {
                try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: file.temporaryURL, to: destination)
            } catch {
                outcome.refused.append(name); continue
            }
            let kind = file.dedupeKey != nil || ChatAttachmentNaming.kind(forName: unique) == .photo ? ChatAttachmentKind.photo : .file
            let item = ChatAttachmentItem(id: id, kind: kind, name: unique, byteCount: size,
                                          relativePath: relative, contentType: file.contentType, sourceKey: file.dedupeKey)
            outcome.added.append(item)
            taken.insert(unique)
            if let key = file.dedupeKey ?? dedupeIdentity(name: name, size: size) { seen.insert(key) }
            room -= 1
            conversationBytes += size
        }
        return outcome
    }

    /// Removes the app's own copy of an attachment that was never sent.
    func discard(_ items: [ChatAttachmentItem]) {
        for item in items { try? FileManager.default.removeItem(at: url(for: item).deletingLastPathComponent()) }
    }

    /// A deleted conversation takes its attachments with it, as on Android, except
    /// files a branch made from it still shows ("<conversation>/<attachment id>").
    func deleteConversation(_ conversationID: String, keeping referenced: Set<String>) {
        let manager = FileManager.default
        let folder = root.appendingPathComponent(conversationID, isDirectory: true)
        guard let children = try? manager.contentsOfDirectory(atPath: folder.path) else { return }
        for child in children where !referenced.contains(conversationID + "/" + child) {
            try? manager.removeItem(at: folder.appendingPathComponent(child, isDirectory: true))
        }
        if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? manager.removeItem(at: folder) }
    }

    /// The attachment folders ("<conversation>/<attachment id>") that saved turns still show.
    static func referencedFolders(in conversations: [ArchivedConversation]) -> Set<String> {
        Set(conversations.flatMap { $0.turns.flatMap(\.attachments) }
            .map { $0.relativePath.split(separator: "/").prefix(2).joined(separator: "/") })
    }

    /// Attachments can be large and are recreated by the user, so they stay out of backups.
    private func prepareRoot() {
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(values)
    }

    private func dedupeIdentity(name: String, size: Int64) -> String? {
        size >= 0 ? "file:\(name):\(size)" : nil
    }

    private func folderBytes(_ folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func freeBytes() -> Int64 {
        let values = try? root.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max / 2
    }
}

extension ChatAttachmentItem {
    /// A sent item drops its library source, so it equals its archived form.
    var sent: ChatAttachmentItem {
        var copy = self
        copy.sourceKey = nil
        return copy
    }

    init(archived: ArchivedAttachment) {
        self.init(id: archived.id, kind: archived.isPhoto ? .photo : .file, name: archived.name,
                  byteCount: archived.byteCount, relativePath: archived.relativePath, contentType: archived.contentType)
    }

    func archived() throws -> ArchivedAttachment {
        try ArchivedAttachment(id: id, isPhoto: kind == .photo, name: name, byteCount: byteCount,
                               relativePath: relativePath, contentType: contentType)
    }
}

enum ChatAttachmentImport {
    /// Picker copies that never reached the tray are deleted right away.
    static func discardTemporary(_ picked: [ChatPickedFile]) {
        for file in picked { try? FileManager.default.removeItem(at: file.temporaryURL.deletingLastPathComponent()) }
    }
}

extension ChatAttachmentImport {
    /// A camera shot goes into the same temporary import layout as picked files,
    /// named like Android's IMG_yyyyMMdd_HHmmss.jpg.
    static func temporaryPhoto(jpeg: Data) -> ChatPickedFile? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let name = "IMG_" + formatter.string(from: Date()) + ".jpg"
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImports/" + UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .atomic)
        } catch { return nil }
        return ChatPickedFile(temporaryURL: url, suggestedName: name, contentType: "public.jpeg", dedupeKey: nil)
    }
}

/// The system pickers the attach panel opens as sheets.
enum ChatAttachPicker: String, Identifiable {
    case album, files
    var id: String { rawValue }
}
