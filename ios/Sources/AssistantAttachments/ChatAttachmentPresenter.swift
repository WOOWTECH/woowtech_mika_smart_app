import AssistantModels
import Foundation

/// Fixed labels only: the review must not display attachment bytes or arbitrary
/// file/provider text as a supposed disclosure.
public enum ChatAttachmentAdditionalData: String, CaseIterable, Sendable, Hashable {
    case systemInstructions, currentQuestion, conversationHistory, profile, memory, skills, toolData
}

/// Non-secret host-provided review snapshot. The host MUST mint new revision
/// IDs when credentials, prompt, conversation, references or their policy
/// change, and must call updateContext before any take or send.
public struct ChatAttachmentReviewContext: Sendable, Equatable {
    public let baseURL: URL
    public let model: String
    public let credentialRevision: UUID
    public let inputRevision: UUID
    public let additionalData: Set<ChatAttachmentAdditionalData>
    public let vision: ModelVisionCapability

    public init(baseURL: URL, model: String, credentialRevision: UUID, inputRevision: UUID,
                additionalData: Set<ChatAttachmentAdditionalData>, vision: ModelVisionCapability) throws {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              baseURL.absoluteString.utf8.count <= 4096,
              !baseURL.absoluteString.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.utf8.count <= 1024,
              !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw ChatAttachmentPresentationError.invalidContext }
        self.baseURL = baseURL; self.model = model; self.credentialRevision = credentialRevision
        self.inputRevision = inputRevision; self.additionalData = additionalData; self.vision = vision
    }
}

public enum ChatAttachmentPresentationError: Error, LocalizedError, Sendable, Equatable {
    case pickerFailed, invalidContext, contextChanged, confirmationRequired, visionUnknown, visionUnsupported
    case importing(ChatAttachmentImportError)
    public var errorDescription: String? {
        switch self {
        case .pickerFailed: return "無法取得選取的檔案；請重新選取。"
        case .invalidContext: return "模型目的地或傳送範圍尚未準備完成。"
        case .contextChanged: return "目的地或傳送內容已變更，請重新確認附件。"
        case .confirmationRequired: return "請先確認本次附件的傳送範圍。"
        case .visionUnknown: return "此模型的圖片支援狀態未知，無法確認傳送。"
        case .visionUnsupported: return "此模型不支援圖片，無法確認傳送。"
        case .importing(let error): return error.errorDescription
        }
    }
}

public enum ChatAttachmentPresentationPhase: Sendable, Equatable {
    case empty, loading(filename: String), ready(ChatAttachmentMetadata)
    case confirmed(ChatAttachmentMetadata), taking(ChatAttachmentMetadata), consumed
}
public struct ChatAttachmentPresentationState: Sendable, Equatable {
    public let phase: ChatAttachmentPresentationPhase
    public let error: ChatAttachmentPresentationError?
    public let context: ChatAttachmentReviewContext?
}

/// State contains a filename and destination URL, which may be sensitive. It
/// exposes no attachment bytes, selected file URL, model key or network client.
/// The host owns this object across sheet presentation and MUST discard it when
/// the draft/conversation is abandoned. It also owns any value returned by take.
@MainActor public final class ChatAttachmentPresenter {
    public private(set) var state = ChatAttachmentPresentationState(phase: .empty, error: nil, context: nil) {
        didSet { onChange?(state) }
    }
    public var onChange: (@MainActor (ChatAttachmentPresentationState) -> Void)?
    private var session: ChatAttachmentImportSession?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var approval: ChatAttachmentReviewContext?
    private let scope: any PickerSecurityScope
    private let makeReader: () -> any ChatAttachmentFileReading
    private let decoder: any ChatAttachmentImageValidating
    // Internal scheduling seam lets the offline regression observe task
    // creation synchronously; production still uses the normal actor task.
    private let schedulePreparation: (@escaping @MainActor () async -> Void) -> Task<Void, Never>

    public convenience init() {
        self.init(scope: URLPickerSecurityScope(), makeReader: { CoordinatedAttachmentReader() }, decoder: ImageIOAttachmentValidator())
    }
    init(scope: any PickerSecurityScope, makeReader: @escaping () -> any ChatAttachmentFileReading,
         decoder: any ChatAttachmentImageValidating,
         schedulePreparation: @escaping (@escaping @MainActor () async -> Void) -> Task<Void, Never> = { operation in
             Task { await operation() }
         }) {
        self.scope = scope; self.makeReader = makeReader; self.decoder = decoder
        self.schedulePreparation = schedulePreparation
    }
    deinit {
        preparation?.cancel()
        if let session { Task { await session.discard() } }
    }

    /// Call synchronously and only from the successful system picker callback.
    /// A failed replacement revokes and discards any previous attachment;
    /// cancellation alone preserves it. A fresh choice or discard is required.
    public func picked(_ url: URL) {
        let selection: ChatAttachmentSelection
        do { selection = try ChatAttachmentSelection(userSelectedURL: url) }
        catch let error as ChatAttachmentImportError { selectionFailed(.importing(error)); return }
        catch { selectionFailed(.pickerFailed); return }
        let reader = PickerScopedAttachmentReader(url: url, scope: scope, delegate: makeReader())
        let next = ChatAttachmentImportSession(selection: selection, reader: reader, decoder: decoder)
        clearSession()
        let id = generation
        session = next
        state = .init(phase: .loading(filename: selection.filename), error: nil, context: state.context)
        // Publishing can synchronously invoke onChange, which may discard or
        // replace this selection before any preparation task exists. Never
        // start a reader for a session invalidated by that callback.
        guard generation == id, session === next else {
            Task.detached { reader.cancel() }
            Task { await next.discard() }
            return
        }
        preparation = schedulePreparation { [weak self, next] in
            do {
                let metadata = try await next.load()
                guard let self, self.generation == id, !Task.isCancelled else { await next.discard(); return }
                self.preparation = nil
                self.state = .init(phase: .ready(metadata), error: nil, context: self.state.context)
            } catch {
                guard let self, self.generation == id else { await next.discard(); return }
                self.preparation = nil; self.session = nil
                let reason = (error as? ChatAttachmentImportError) ?? .unreadable
                self.state = .init(phase: .empty, error: .importing(reason), context: self.state.context)
                await next.discard()
            }
        }
    }

    /// Cancellation is not an error and preserves the existing attachment.
    public func pickerCancelled() {}
    public func pickerFailed() { selectionFailed(.pickerFailed) }

    public func updateContext(_ context: ChatAttachmentReviewContext?) {
        guard state.context != context else { return }
        approval = nil
        let phase: ChatAttachmentPresentationPhase
        switch state.phase {
        case .confirmed(let metadata): phase = .ready(metadata)
        default: phase = state.phase
        }
        // Selection failures require a fresh selection or explicit discard.
        // Contextual errors can be reconsidered only after context changes.
        let error: ChatAttachmentPresentationError?
        switch state.error {
        case .pickerFailed, .importing: error = state.error
        default: error = nil
        }
        state = .init(phase: phase, error: error, context: context)
    }

    public func confirm() throws {
        do {
            if let error = state.error { throw error }
            guard case .ready(let metadata) = state.phase else { throw ChatAttachmentPresentationError.confirmationRequired }
            guard let context = state.context else { throw ChatAttachmentPresentationError.invalidContext }
            try Self.validateVision(metadata, context: context)
            approval = context
            state = .init(phase: .confirmed(metadata), error: nil, context: context)
        } catch let error as ChatAttachmentPresentationError {
            publish(error: error)
            throw error
        }
    }

    /// Transfers a one-shot value; never sends it. The host must revalidate the
    /// exact same live context after suspension and immediately before network.
    public func takeConfirmed(context: ChatAttachmentReviewContext) async throws -> ModelAttachment {
        guard state.error == nil, case .confirmed(let metadata) = state.phase,
              let session, approval == context, state.context == context else {
            throw ChatAttachmentPresentationError.confirmationRequired
        }
        try Self.validateVision(metadata, context: context)
        let id = generation
        state = .init(phase: .taking(metadata), error: nil, context: context)
        do {
            let attachment = try await session.take()
            guard !Task.isCancelled, generation == id, approval == context, state.context == context,
                  state.phase == .taking(metadata) else { throw ChatAttachmentPresentationError.contextChanged }
            self.session = nil; approval = nil
            state = .init(phase: .consumed, error: nil, context: context)
            return attachment
        } catch {
            if generation == id {
                clearSession()
                state = .init(phase: .empty, error: .contextChanged, context: state.context)
            }
            throw (error as? ChatAttachmentPresentationError) ?? .contextChanged
        }
    }

    public func discard() {
        clearSession()
        state = .init(phase: .empty, error: nil, context: state.context)
    }

    private func clearSession() {
        generation = UUID(); approval = nil; preparation?.cancel(); preparation = nil
        if let previous = session { Task { await previous.discard() } }
        session = nil
    }
    private func selectionFailed(_ error: ChatAttachmentPresentationError) {
        clearSession()
        state = .init(phase: .empty, error: error, context: state.context)
    }
    private func publish(error: ChatAttachmentPresentationError) {
        state = .init(phase: state.phase, error: error, context: state.context)
    }
    private static func validateVision(_ metadata: ChatAttachmentMetadata, context: ChatAttachmentReviewContext) throws {
        guard metadata.kind != .text else { return }
        switch context.vision {
        case .unknown: throw ChatAttachmentPresentationError.visionUnknown
        case .unsupported: throw ChatAttachmentPresentationError.visionUnsupported
        case .supported: return
        }
    }
}
