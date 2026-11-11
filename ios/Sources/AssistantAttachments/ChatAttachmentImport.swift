import AssistantModels
import Foundation

/// Construct only from an explicit document/photo picker result. Constructing
/// a selection does not open the URL, grant access or persist a bookmark.
public struct ChatAttachmentSelection: Sendable {
    let url: URL
    public let filename: String
    public let kind: ChatAttachmentKind

    public init(userSelectedURL url: URL) throws {
        guard url.isFileURL, (url.host ?? "").isEmpty, url.query == nil, url.fragment == nil else {
            throw ChatAttachmentImportError.invalidSelection
        }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.unicodeScalars.contains(where: { scalar in
                  CharacterSet.controlCharacters.contains(scalar) || scalar.properties.generalCategory == .format
              }) else { throw ChatAttachmentImportError.invalidSelection }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": kind = .jpeg
        case "png": kind = .png
        case "txt", "md", "csv", "tsv": kind = .text
        default: throw ChatAttachmentImportError.unsupportedType
        }
        self.url = url; filename = name
    }
}

public enum ChatAttachmentKind: String, Sendable, Equatable {
    case jpeg, png, text
    var maximumBytes: Int { self == .text ? ModelAttachment.maximumTextBytes : ModelAttachment.maximumImageBytes }
    var mime: String { self == .png ? "image/png" : "image/jpeg" }
}

public struct ChatAttachmentMetadata: Sendable, Equatable {
    public let filename: String
    public let byteCount: Int
    public let kind: ChatAttachmentKind
}

/// This is not a Codable state, a filesystem grant, or a model message.
public enum ChatAttachmentImportState: Sendable, Equatable {
    case selected, loading, ready(ChatAttachmentMetadata), consumed, discarded, failed(ChatAttachmentImportError)
}

public enum ChatAttachmentImportError: Error, LocalizedError, Sendable, Equatable {
    case invalidSelection, unsupportedType, unreadable, tooLarge, empty, invalidFormat, imageTooLarge
    case cancelled, timedOut, invalidState
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: return "無法使用這個選取項目。"
        case .unsupportedType: return "僅支援 JPEG、PNG 或 UTF-8 文字檔。"
        case .unreadable: return "無法讀取選取的檔案，請重新選取。"
        case .tooLarge: return "檔案超過大小限制。"
        case .empty: return "選取的檔案是空的。"
        case .invalidFormat: return "檔案格式無效或內容不完整。"
        case .imageTooLarge: return "圖片像素過多，無法安全解碼。"
        case .cancelled: return "已取消附件匯入。"
        case .timedOut: return "附件讀取逾時，請重新選取。"
        case .invalidState: return "附件已使用、移除或尚未準備完成。"
        }
    }
}

/// Inject only a fresh, per-operation reader. Implementations must not write or
/// retain bytes and should poll isCancelled. A cancelled read can finish late;
/// the operation gate prevents its result from becoming available to the host.
public protocol ChatAttachmentFileReading: Sendable {
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data
    func cancel()
}

/// Validation must fully decode/rasterize, check the declared MIME and bound
/// decoded dimensions. Errors must not include input bytes or paths.
public protocol ChatAttachmentImageValidating: Sendable {
    func validate(data: Data, mimeType: String) throws
}

/// One selection, one in-memory result, and at most one take(). No URL,
/// attachment bytes or state are Codable or written to disk by this session.
public actor ChatAttachmentImportSession {
    public private(set) var state: ChatAttachmentImportState = .selected
    private var selection: ChatAttachmentSelection?
    private var result: ModelAttachment?
    private var operation: ChatAttachmentReadOperation?
    private let reader: any ChatAttachmentFileReading
    private let decoder: any ChatAttachmentImageValidating
    private let timeout: TimeInterval

    public init(selection: ChatAttachmentSelection,
                reader: any ChatAttachmentFileReading = CoordinatedAttachmentReader(),
                decoder: any ChatAttachmentImageValidating = ImageIOAttachmentValidator(),
                timeout: TimeInterval = 30) {
        self.selection = selection; self.reader = reader; self.decoder = decoder
        self.timeout = timeout.isFinite ? min(30, max(0.01, timeout)) : 30
    }

    @discardableResult public func load() async throws -> ChatAttachmentMetadata {
        guard state == .selected, let selection else { throw ChatAttachmentImportError.invalidState }
        self.selection = nil
        let op = ChatAttachmentReadOperation(selection: selection, reader: reader, decoder: decoder, timeout: timeout)
        operation = op; state = .loading
        do {
            let loaded = try await withTaskCancellationHandler {
                try Task.checkCancellation()
                return try await op.run()
            } onCancel: { op.cancel(.cancelled) }
            guard operation === op, state == .loading, !Task.isCancelled else {
                op.cancel(.cancelled)
                if operation === op { operation = nil; state = .discarded }
                throw ChatAttachmentImportError.cancelled
            }
            operation = nil; result = loaded.attachment; state = .ready(loaded.metadata)
            return loaded.metadata
        } catch {
            let reason = (error as? ChatAttachmentImportError) ?? (error is CancellationError ? .cancelled : .unreadable)
            if operation === op {
                operation = nil; result = nil
                state = reason == .cancelled ? .discarded : .failed(reason)
            }
            throw reason
        }
    }

    /// Ownership transfers to the caller. The caller must discard all copies on
    /// send cancellation/end; Swift value copies cannot be remotely revoked.
    public func take() throws -> ModelAttachment {
        guard case .ready = state, let result else { throw ChatAttachmentImportError.invalidState }
        self.result = nil; state = .consumed
        return result
    }

    /// Discards pending metadata, bytes and future result publication. An active
    /// provider/decoder may finish later but cannot repopulate this session.
    public func discard() {
        selection = nil; result = nil
        operation?.cancel(.cancelled); operation = nil; state = .discarded
    }
}

struct LoadedChatAttachment: Sendable {
    let metadata: ChatAttachmentMetadata
    let attachment: ModelAttachment
}

/// Resolves cancellation/deadline once without waiting for a stuck provider or
/// a synchronous image decoder; late results are discarded under the lock.
final class ChatAttachmentReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let selection: ChatAttachmentSelection
    private let reader: any ChatAttachmentFileReading
    private let decoder: any ChatAttachmentImageValidating
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<LoadedChatAttachment, Error>?
    private var terminal: Result<LoadedChatAttachment, Error>?

    init(selection: ChatAttachmentSelection, reader: any ChatAttachmentFileReading,
         decoder: any ChatAttachmentImageValidating, timeout: TimeInterval) {
        self.selection = selection; self.reader = reader; self.decoder = decoder; self.timeout = timeout
    }
    func run() async throws -> LoadedChatAttachment {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let terminal { lock.unlock(); continuation.resume(with: terminal); return }
            self.continuation = continuation; lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { self.perform() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in self?.cancel(.timedOut) }
        }
    }
    func cancel(_ reason: ChatAttachmentImportError) {
        // A provider or injected reader may block even in cancel(). Resolve
        // the session first and keep its actor/caller free to discard state.
        if finish(.failure(reason)) {
            let reader = reader
            DispatchQueue.global(qos: .utility).async { reader.cancel() }
        }
    }
    private func isCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return terminal != nil
    }
    @discardableResult private func finish(_ result: Result<LoadedChatAttachment, Error>) -> Bool {
        lock.lock()
        guard terminal == nil else { lock.unlock(); return false }
        terminal = result; let pending = continuation; continuation = nil
        lock.unlock(); pending?.resume(with: result); return true
    }
    private func perform() {
        do {
            guard !isCancelled() else { return }
            let data = try reader.read(url: selection.url, maximumBytes: selection.kind.maximumBytes, isCancelled: { self.isCancelled() })
            guard !isCancelled() else { return }
            guard !data.isEmpty else { throw ChatAttachmentImportError.empty }
            guard data.count <= selection.kind.maximumBytes else { throw ChatAttachmentImportError.tooLarge }
            let attachment: ModelAttachment
            do {
                if selection.kind == .text { attachment = try .text(utf8: data) }
                else {
                    attachment = try .image(data: data, mimeType: selection.kind.mime)
                    try decoder.validate(data: data, mimeType: selection.kind.mime)
                }
            } catch let error as ChatAttachmentImportError { throw error }
            catch let error as ModelAttachmentError {
                switch error {
                case .empty: throw ChatAttachmentImportError.empty
                case .tooLarge: throw ChatAttachmentImportError.tooLarge
                default: throw ChatAttachmentImportError.invalidFormat
                }
            } catch { throw ChatAttachmentImportError.invalidFormat }
            guard !isCancelled() else { return }
            let metadata = ChatAttachmentMetadata(filename: selection.filename, byteCount: data.count, kind: selection.kind)
            finish(.success(LoadedChatAttachment(metadata: metadata, attachment: attachment)))
        } catch let error as ChatAttachmentImportError { finish(.failure(error)) }
        catch { finish(.failure(ChatAttachmentImportError.unreadable)) }
    }
}
