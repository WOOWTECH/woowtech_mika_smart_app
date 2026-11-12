import AssistantModels
import AssistantMCP
import AssistantMemory
import AssistantPersistence
import AssistantSkills
import AssistantAttachments
import Combine
import Foundation

struct ModelAccess {
    let client: any ChatModelClient
    let configuration: ModelConfiguration
    let key: String
}

struct ChatEntry: Identifiable {
    let id: UUID
    let role: String
    let content: String
    let pdf: ArchivedPDFAnswer?
    init(id: UUID = UUID(), role: String, content: String, pdf: ArchivedPDFAnswer? = nil) {
        self.id = id; self.role = role; self.content = content
        self.pdf = pdf
    }
}

/// Display-only text from one unfinished plain request. It never becomes a
/// ChatEntry, archive turn, learning utterance or notification completion.
struct ChatReplyPreview: Identifiable, Equatable {
    enum Phase { case receiving, cancelled, failed }
    static let maximumUTF8Bytes = 4 * 1024 * 1024
    let id: UUID
    let text: String
    var phase: Phase
    var status: String {
        switch phase {
        case .receiving: return "回覆產生中・尚未完成，未保存"
        case .cancelled: return "已取消・部分回覆未保存"
        case .failed: return "回覆未完成・部分回覆未保存"
        }
    }
}

struct MCPApprovalRequest: Identifiable {
    let id = UUID()
    let name: String
    let arguments: JSONValue
    var argumentsText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// Prepared for reviewed attachment tool turns; not connected to `send` yet.
/// The archive is checked under its cooperative cross-store lock for *each*
/// model call, and the lease follows the actual completion rather than the
/// MCP runner's independently cancellable consumer. The caller supplies a
/// synchronous main-actor validation of the complete reviewed session state.
/// Without a store, the trusted host must explicitly declare a brand-new,
/// unarchived conversation with no prior history or quote. This flag is a
/// host assertion, not a way to discover whether omitted sources exist.
struct AttachmentToolLeasedClient: LifetimeBoundCompletionChatModelClient {
    let client: any LifetimeBoundCompletionChatModelClient
    let archive: ConversationArchiveStore?
    let conversationID: UUID
    let expected: ArchivedConversation?
    let quoteSource: ArchivedConversation?
    let validate: @MainActor @Sendable () throws -> Void
    let unarchivedNewConversation: Bool

    init(client: any LifetimeBoundCompletionChatModelClient, archive: ConversationArchiveStore?,
         conversationID: UUID, expected: ArchivedConversation?, quoteSource: ArchivedConversation?,
         validate: @escaping @MainActor @Sendable () throws -> Void, unarchivedNewConversation: Bool = false) {
        self.client = client; self.archive = archive; self.conversationID = conversationID
        self.expected = expected; self.quoteSource = quoteSource; self.validate = validate
        self.unarchivedNewConversation = unarchivedNewConversation
    }

    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try Task.checkCancellation()
        let lease = try await MainActor.run {
            try Task.checkCancellation()
            if archive == nil {
                guard unarchivedNewConversation, expected == nil, quoteSource == nil else {
                    throw ConversationArchiveError.unavailable
                }
            } else if unarchivedNewConversation {
                throw ConversationArchiveError.unavailable
            }
            try validate()
            let lease = try archive?.acquireAttachmentRequestLease(conversationID: conversationID,
                expected: expected, quoteSource: quoteSource)
            do {
                try Task.checkCancellation()
                try validate()
                return lease
            } catch {
                lease?.release()
                throw error
            }
        }
        // Cancellation of the runner can finish its consumer before this
        // method's client returns. Never release a live producer's lease.
        defer { withExtendedLifetime(lease) {} }
        try Task.checkCancellation()
        let reply = try await client.complete(messages: messages, configuration: configuration, apiKey: apiKey)
        try Task.checkCancellation()
        return reply
    }
}

/// An in-memory consent snapshot. Never encoded, logged or stored in history.
private struct AttachmentBinding: Equatable {
    let destination: ConversationDestination
    let conversationID: String
    let draft: String
    let quote: ConversationQuote.Quote?
    let quoteSource: ArchivedConversation?
    let history: [ModelMessage]
    let archivePrior: ArchivedConversation?
    var learningGeneration: UUID
    let learningAvailable: Bool
    let memory: MemoryState
    let profile: UserProfileState
    let skills: SkillsState
    let vision: ModelVisionCapability
    let revision: UUID
}

@MainActor
final class ChatSession: ObservableObject {
    static let plainRequestDeadlineSeconds: UInt64 = 90
    let learning: LearningStore
    let archive: ConversationArchiveStore?
    @Published private(set) var conversationID = UUID().uuidString
    private var conversationDestination: ConversationDestination?
    @Published private(set) var archiveNotice: String?
    private var pendingArchiveSave: (record: ArchivedConversation, expected: ArchivedConversation?)?
    var canRetryArchiveSave: Bool { pendingArchiveSave != nil && !isSubmitting }
    @Published var draft = "" { didSet { if draft != oldValue { invalidateAttachmentReview() } } }
    @Published private(set) var pendingQuote: ConversationQuote.Quote? { didSet { if pendingQuote != oldValue { invalidateAttachmentReview() } } }
    private var quoteSource: ArchivedConversation?
    @Published var baseURLDraft = ""
    @Published var modelDraft = ""
    @Published var keyDraft = ""
    @Published private(set) var entries: [ChatEntry] = [] { didSet { invalidateAttachmentReview() } }
    @Published private(set) var replyPreview: ChatReplyPreview?
    @Published private(set) var pdfAttachment: ChatPDFAttachment?
    private var pdfChanges: AnyCancellable?
    @Published private(set) var savedSettings: SavedModelSettings?
    @Published private(set) var hasStoredKey = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var chatError: String?
    @Published private(set) var chatNotice: String?
    @Published private(set) var settingsError: String?
    @Published private(set) var settingsNotice: String?
    @Published var usesMCP = false { didSet { if usesMCP != oldValue { invalidateAttachmentReview() } } }
    /// Future composer hosts this exact presenter; it never owns a model client.
    let attachmentPresenter = ChatAttachmentPresenter()
    @Published private(set) var attachmentIssue: AppText?
    private var attachmentBinding: AttachmentBinding?
    private var attachmentRevision = UUID()
    private var attachmentRequiresDecision = false
    private var attachmentRequestID: UUID?
    @Published private(set) var pendingMCPApproval: MCPApprovalRequest?
    @Published private(set) var mcpActivity: String?
    @Published private(set) var mcpSteps: [MCPConversationStep] = []
    @Published private(set) var mcpDiagnostics: String?
    @Published private(set) var pendingProfileReview: UserProfileToolReview?
    @Published private(set) var profileReceipt: UserProfileToolReceipt?
    private var profileReceiptRequestID: UUID?
    private var profileApprovalContinuation: CheckedContinuation<Bool, Never>?
    @Published private(set) var pendingMemoryReview: MemoryToolReview?
    @Published private(set) var memoryReceipt: MemoryToolReceipt?
    private var memoryReceiptRequestID: UUID?
    private var memoryApprovalContinuation: CheckedContinuation<Bool, Never>?
    private var mcpPhase = "idle"
    private var mcpModelCalls = 0
    private var mcpFormatCorrections = 0
    private var mcpApprovalContinuation: CheckedContinuation<Bool, Never>?
    private var isMCPRun = false
    private var mcpSentCount = 0

    #if DEBUG
    @Published private(set) var pdfModelRequestEvents = 0
    #endif
    let isUITestMode: Bool
    private let repository: ModelSettingsRepository
    private let client: any ChatModelClient
    private let assistantQuoteText: @MainActor (String) -> String
    private let attachmentPreflightProbe: @MainActor () async -> Void
    private let attachmentClientStartProbe: @MainActor () -> Void
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var requestID: UUID?
    /// Read-only completion handle for joining an already captured task after cancellation.
    var capturedArchiveRequest: Task<Void, Never>? { request }

    init() {
        assistantQuoteText = Self.plainAssistantQuote
        attachmentPreflightProbe = {}
        attachmentClientStartProbe = {}
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        _ = ChatAttachmentComposerUITestFixture.selected(arguments: arguments)
        let streamFixture: UITestChatStreamingConfiguration?
        let pdfFixture: ChatPDFUITestConfiguration?
        do {
            streamFixture = try UITestChatStreamingConfiguration.resolve(arguments: arguments)
            pdfFixture = try ChatPDFUITestConfiguration.resolve(arguments: arguments)
        }
        catch { preconditionFailure("Chat UI fixture requires one isolated UI test mode and UUID namespace; no Live mode") }
        #endif
        learning = LearningStore()
        archive = ConversationArchiveStore()
        var bootstrapFailure: String?
        #if DEBUG
        precondition(!(arguments.contains("-UITestMode") && arguments.contains("-LiveModelUITest")), "Choose one UI test mode")
        if arguments.contains("-LiveModelUITest") {
            repository = LiveModelUITestSupport.repository(arguments: arguments)
            client = HTTPChatModelClient()
            isUITestMode = false
            do {
                if arguments.contains("-LiveModelUITestCleanup") {
                    try repository.remove()
                } else {
                    try LiveModelUITestSupport.bootstrap(repository, environment: ProcessInfo.processInfo.environment)
                }
            }
            catch { bootstrapFailure = Self.settingsMessage(error) }
        } else if arguments.contains("-UITestMode") {
            repository = UITestModelFixture.repository(arguments: arguments)
            if let pdfFixture { client = UITestPDFChatModelClient(configuration: pdfFixture) }
            else if let streamFixture { client = UITestStreamingChatModelClient(configuration: streamFixture) }
            else { client = UITestChatModelClient() }
            isUITestMode = true
        } else {
            repository = Self.liveRepository()
            client = HTTPChatModelClient()
            isUITestMode = false
        }
        #else
        repository = Self.liveRepository()
        client = HTTPChatModelClient()
        isUITestMode = false
        #endif
        loadSettings()
        if let bootstrapFailure { settingsError = "Live UI 測試設定未完成。\(bootstrapFailure)" }
    }

    /// Dependency boundary for exercising actual App transactions and request
    /// lifecycles with isolated storage; production uses the initializer above.
    init(learning: LearningStore, repository: ModelSettingsRepository, client: any ChatModelClient,
         archive: ConversationArchiveStore? = nil,
         assistantQuoteText: @escaping @MainActor (String) -> String = ChatSession.plainAssistantQuote,
         attachmentPreflightProbe: @escaping @MainActor () async -> Void = {},
         attachmentClientStartProbe: @escaping @MainActor () -> Void = {}) {
        self.learning = learning
        self.archive = archive
        self.repository = repository
        self.client = client
        self.assistantQuoteText = assistantQuoteText
        self.attachmentPreflightProbe = attachmentPreflightProbe
        self.attachmentClientStartProbe = attachmentClientStartProbe
        isUITestMode = false
        loadSettings()
    }

    static func plainAssistantQuote(_ text: String) -> String {
        #if os(iOS)
        return ChatReplyMarkdown.parse(text).visibleText
        #else
        // Hosted tests inject the platform renderer; SwiftUI is unavailable in CLT.
        return text
        #endif
    }

    private func loadSettings() {
        do {
            savedSettings = try repository.load()
            if let savedSettings {
                baseURLDraft = savedSettings.baseURL.absoluteString
                modelDraft = savedSettings.model
                _ = try repository.key(for: savedSettings)
                hasStoredKey = true
            }
        } catch {
            settingsError = Self.settingsMessage(error)
        }
    }

    var canSend: Bool {
        savedSettings != nil && hasStoredKey && !isSubmitting
            && quoteSourceIsCurrent
            && (conversationDestination == nil || conversationDestination == archiveDestination)
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (pdfAttachment == nil || (pdfAttachment?.isReady == true && !usesMCP))
            && attachmentCanSend
    }

    private var quoteSourceIsCurrent: Bool {
        guard pendingQuote != nil else { return quoteSource == nil }
        guard let source = quoteSource, let archive, archive.available,
              archive.state.conversations.first(where: { $0.id == source.id }) == source else { return false }
        return matchesArchivedTranscript(source)
    }

    var archiveDestination: ConversationDestination? {
        guard let savedSettings, let account = UUID(uuidString: savedSettings.credentialAccount) else { return nil }
        return try? ConversationDestination(baseURL: savedSettings.baseURL.absoluteString,
            model: savedSettings.model, credentialAccount: account)
    }

    func canOpenConversation(_ record: ArchivedConversation) -> Bool {
        archive?.available == true && hasStoredKey && archiveDestination == record.destination
    }

    func isCurrentConversation(id: UUID) -> Bool { conversationID == id.uuidString }

    /// Reject stale menus, unfinished previews and completed replies that have
    /// not yet been saved. Compare the entire visible transcript, not just IDs.
    private func matchesArchivedTranscript(_ record: ArchivedConversation) -> Bool {
        let expected = record.turns.flatMap { turn in
            [ChatEntry(id: turn.userID, role: "user", content: turn.userText, pdf: turn.pdf),
             ChatEntry(id: turn.assistantID, role: "assistant", content: turn.assistantText)]
        }
        return isCurrentConversation(id: record.id) && entries.count == expected.count
            && zip(entries, expected).allSatisfy { actual, saved in
                actual.id == saved.id && actual.role == saved.role && actual.content == saved.content && actual.pdf == saved.pdf
            }
    }

    @discardableResult func selectQuote(messageID: UUID, expectedContent: String, in conversationID: UUID) -> Bool {
        guard !isSubmitting, replyPreview == nil, pendingArchiveSave == nil, let archive else { return false }
        archive.reload()
        guard archive.available,
              let record = archive.state.conversations.first(where: { $0.id == conversationID }),
              matchesArchivedTranscript(record),
              let entry = entries.first(where: { $0.id == messageID }), entry.content == expectedContent else { return false }
        let source: ConversationQuote.Source
        let text: String
        switch entry.role {
        case "user": source = .user; text = ConversationQuote.parse(entry.content).words
        case "assistant": source = .assistant; text = assistantQuoteText(entry.content)
        default: return false
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        pendingQuote = .init(source: source, text: trimmed)
        quoteSource = record
        return true
    }

    func clearQuote() { guard !isSubmitting else { return }; pendingQuote = nil; quoteSource = nil }

    /// Drafts and attachments cannot be silently discarded by branching.
    private var branchHasUnfinishedOrUnsavedWork: Bool {
        replyPreview != nil || pendingArchiveSave != nil || archiveNotice != nil
            || !draft.isEmpty || pendingQuote != nil || pdfAttachment != nil || hasGeneralAttachment
    }

    func prepareBranch(source: ArchivedConversation, assistantID: UUID, title: String,
                       targetID: UUID = UUID(), at: Date = Date()) throws -> ConversationBranchPlan {
        guard !isSubmitting else { throw ConversationBranchError.blocked }
        guard !branchHasUnfinishedOrUnsavedWork else { throw ConversationBranchError.unfinishedTurn }
        guard let archive else { throw ConversationBranchError.staleSource }
        archive.reload()
        guard archive.available, canOpenConversation(source), matchesArchivedTranscript(source) else {
            throw ConversationBranchError.staleSource
        }
        return try .prepare(in: archive.state, source: source, assistantID: assistantID, targetID: targetID,
                            title: title, at: at, isBusy: isSubmitting,
                            hasUnfinishedOrUnsavedTurn: branchHasUnfinishedOrUnsavedWork)
    }

    @discardableResult func commitBranch(_ plan: ConversationBranchPlan) throws -> UUID {
        guard let archive, archive.available, canOpenConversation(plan.source), matchesArchivedTranscript(plan.source) else {
            throw ConversationBranchError.staleSource
        }
        try archive.commitBranch(plan, isBusy: isSubmitting,
                                 hasUnfinishedOrUnsavedTurn: branchHasUnfinishedOrUnsavedWork)
        // No suspension occurs between persistence and opening. If opening ever
        // becomes unavailable, the saved branch remains recoverable in archive.
        guard openConversation(id: plan.branch.id) else { throw ConversationArchiveError.unavailable }
        return plan.branch.id
    }

    @discardableResult func openConversation(id: UUID) -> Bool {
        guard pendingQuote == nil, !hasGeneralAttachment, let record = archive?.state.conversations.first(where: { $0.id == id }),
              canOpenConversation(record) else { return false }
        // Publish restored entries only after submitting and approvals have ended.
        // Restored text cannot complete a notification ticket or resume a task.
        cancel()
        newConversation()
        usesMCP = false
        conversationID = record.id.uuidString
        conversationDestination = record.destination
        draft = ""
        entries = record.turns.flatMap { [ChatEntry(id: $0.userID, role: "user", content: $0.userText, pdf: $0.pdf),
                                         ChatEntry(id: $0.assistantID, role: "assistant", content: $0.assistantText)] }
        chatNotice = "已開啟保存的對話；尚未傳送任何訊息。"
        return true
    }

    @discardableResult func deleteConversation(id: UUID) -> Bool {
        guard !isCurrentConversation(id: id) || (pendingQuote == nil && !hasGeneralAttachment) else { return false }
        if conversationID == id.uuidString { cancel() }
        guard archive?.delete(id: id) == true else { return false }
        if conversationID == id.uuidString { newConversation() }
        return true
    }

    func retryArchiveSave() {
        guard canRetryArchiveSave, let pendingArchiveSave, let archive else { return }
        do {
            if !archive.available { archive.reload() }
            try archive.save(pendingArchiveSave.record, expected: pendingArchiveSave.expected)
            self.pendingArchiveSave = nil; archiveNotice = nil
        } catch { archiveNotice = Self.archiveSaveFailure }
    }

    private static let archiveSaveFailure = "回覆已顯示，但本次對話未能保存；關閉程序後可能遺失。原有保存內容保留，沒有自動刪除舊對話。"

    var hasGeneralAttachment: Bool {
        attachmentRequiresDecision || attachmentPresenter.state.phase != .empty || attachmentPresenter.state.error != nil
    }

    private func currentAttachmentBinding() -> AttachmentBinding? {
        guard let destination = archiveDestination else { return nil }
        return AttachmentBinding(destination: destination, conversationID: conversationID, draft: draft,
            quote: pendingQuote, quoteSource: quoteSource,
            history: entries.map { ModelMessage(role: $0.role, content: $0.content) },
            archivePrior: archive?.state.conversations.first { $0.id.uuidString == conversationID },
            learningGeneration: learning.generation, learningAvailable: learning.available,
            memory: learning.memory, profile: learning.profile, skills: learning.skills,
            vision: savedSettings?.visionCapability ?? .unknown, revision: attachmentRevision)
    }

    private var attachmentCanSend: Bool {
        guard hasGeneralAttachment else { return true }
        guard !attachmentRequiresDecision, !usesMCP, pdfAttachment == nil,
              !(learning.available && learning.memory.preferences.useMemory),
              let binding = attachmentBinding, binding == currentAttachmentBinding(),
              case .confirmed = attachmentPresenter.state.phase,
              attachmentPresenter.state.error == nil,
              attachmentPresenter.state.context == attachmentReviewContext(binding) else { return false }
        return true
    }

    private func attachmentReviewContext(_ binding: AttachmentBinding) -> ChatAttachmentReviewContext? {
        var other: Set<ChatAttachmentAdditionalData> = [.currentQuestion]
        if !binding.history.isEmpty { other.insert(.conversationHistory) }
        if binding.learningAvailable { other.insert(.skills) }
        guard let url = URL(string: binding.destination.baseURL) else { return nil }
        return try? ChatAttachmentReviewContext(baseURL: url, model: binding.destination.model,
            credentialRevision: binding.destination.credentialAccount, inputRevision: binding.revision,
            additionalData: other, vision: binding.vision)
    }

    private func invalidateAttachmentReview() {
        attachmentRevision = UUID()
        attachmentBinding = nil
        attachmentPresenter.updateContext(nil)
    }

    private func setAttachmentIssue(_ issue: AppText) {
        attachmentIssue = issue
        chatError = issue.traditionalFallback
    }

    func explainAttachmentBeforeNewConversation() {
        if hasGeneralAttachment { setAttachmentIssue(.composerAttachmentRemoveBeforeNew) }
    }

    /// Call before presenting the standalone picker and again after any host
    /// input change. The picker confirms the resulting exact context, not bytes.
    /// Image capability comes only from the saved explicit user declaration;
    /// a successful text connection never changes it.
    @discardableResult func prepareAttachmentReview() -> Bool {
        guard !isSubmitting else { return false }
        guard hasStoredKey, savedSettings != nil, (try? repository.load()) == savedSettings,
              let binding = currentAttachmentBinding() else {
            invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentUnavailable); return false
        }
        guard pdfAttachment == nil else { invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentRemoveFirst); return false }
        guard !usesMCP, !(learning.available && learning.memory.preferences.useMemory) else {
            invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentToolsEnabled); return false
        }
        if attachmentRequiresDecision {
            guard case .ready = attachmentPresenter.state.phase else { setAttachmentIssue(.chatAttachmentReselect); return false }
        }
        if attachmentBinding != binding { attachmentRevision = UUID() }
        guard let refreshed = currentAttachmentBinding(), let context = attachmentReviewContext(refreshed) else {
            invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentUnavailable); return false
        }
        attachmentBinding = refreshed
        attachmentPresenter.updateContext(context)
        if case .ready = attachmentPresenter.state.phase { attachmentRequiresDecision = false }
        attachmentIssue = nil; chatError = nil
        return true
    }

    /// Explicit removal also resolves a failed one-shot attempt; never retry it.
    func discardGeneralAttachment() {
        guard attachmentRequestID == nil else { return }
        attachmentPresenter.discard(); attachmentRequiresDecision = false
        invalidateAttachmentReview()
        if attachmentIssue != nil { chatError = nil }
        attachmentIssue = nil
    }

    func generalAttachmentEnteredBackground() {
        if attachmentRequestID != nil { cancel() }
        else { discardGeneralAttachment() }
    }

    private func validateAttachmentStart(binding: AttachmentBinding, context: ChatAttachmentReviewContext,
                                         key: String, id: UUID) throws {
        try Task.checkCancellation()
        guard requestID == id, attachmentRequestID == id,
              try repository.load() == savedSettings,
              attachmentBinding == binding, currentAttachmentBinding() == binding,
              quoteSourceIsCurrent, attachmentPresenter.state.phase == .consumed,
              attachmentPresenter.state.context == context,
              let latest = savedSettings, archiveDestination == binding.destination,
              try repository.key(for: latest) == key else { throw ChatAttachmentPresentationError.contextChanged }
    }

    func modelAccess() throws -> ModelAccess {
        guard let savedSettings, hasStoredKey else { throw HTTPChatModelError.invalidConfiguration }
        return ModelAccess(client: client, configuration: savedSettings.configuration,
                           key: try repository.key(for: savedSettings))
    }

    // Keep the state typed so language changes re-render the current status.
    var chatStatusMessage: AppText {
        if pendingProfileReview != nil { return .chatStatusProfileReview }
        if pendingMemoryReview != nil { return .chatStatusMemoryReview }
        if pendingMCPApproval != nil { return .chatStatusMCPApproval }
        if isSubmitting && isMCPRun { return .chatStatusMCPWorking }
        if isSubmitting { return .chatStatusWaiting }
        return savedSettings != nil && hasStoredKey ? .chatStatusConfigured : .chatStatusUnconfigured
    }

    var chatStatus: String { chatStatusMessage.traditionalFallback }

    /// Commit a user statement only for the exact settings shown at review.
    /// This is independent of any text connection test and changes no key.
    @discardableResult func setModelVision(_ supported: Bool?, expected: SavedModelSettings) -> Bool {
        guard !isSubmitting else { return false }
        guard savedSettings == expected else {
            settingsError = ModelSettingsError.staleSettings.errorDescription; return false
        }
        do {
            let updated = try repository.setVision(supported, expected: expected)
            guard savedSettings == expected else { return false }
            savedSettings = updated
            invalidateAttachmentReview()
            settingsError = nil
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            return false
        }
    }

    func saveSettings() {
        guard !isSubmitting else { return }
        guard pendingQuote == nil else { settingsError = "請先傳送或移除引用，再變更模型設定。"; return }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        do {
            let result = try repository.save(baseURL: baseURLDraft, model: modelDraft, newKey: keyDraft)
            let changed = savedSettings?.baseURL != result.record.baseURL
                || savedSettings?.model != result.record.model
                || savedSettings?.credentialAccount != result.record.credentialAccount
            savedSettings = result.record
            hasStoredKey = true
            baseURLDraft = result.record.baseURL.absoluteString
            modelDraft = result.record.model
            keyDraft = ""
            if changed {
                invalidateAttachmentReview()
                pdfAttachment?.revokeDestination()
                entries = []
                replyPreview = nil
                pendingQuote = nil
                quoteSource = nil
                conversationDestination = nil; archiveNotice = nil; pendingArchiveSave = nil
                profileReceipt = nil
                profileReceiptRequestID = nil
                memoryReceipt = nil
                memoryReceiptRequestID = nil
                conversationID = UUID().uuidString
                learning.resetConversationPresentation()
            }
            chatError = nil
            chatNotice = nil
            settingsNotice = result.cleanupFailed
                ? "新設定已儲存，尚未驗證連線。舊金鑰清理失敗，可用移除功能清除此 App 的模型金鑰。"
                : "設定已儲存，尚未驗證連線。"
        } catch {
            settingsError = Self.settingsMessage(error)
        }
    }

    func removeSettings() {
        guard !isSubmitting else { return }
        guard pendingQuote == nil else { settingsError = "請先傳送或移除引用，再移除模型設定。"; return }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        do {
            try repository.remove()
            invalidateAttachmentReview()
            pdfAttachment?.revokeDestination()
            savedSettings = nil
            hasStoredKey = false
            baseURLDraft = ""
            modelDraft = ""
            keyDraft = ""
            entries = []
            replyPreview = nil
            pendingQuote = nil
            quoteSource = nil
            conversationDestination = nil; archiveNotice = nil; pendingArchiveSave = nil
            profileReceipt = nil
            profileReceiptRequestID = nil
            memoryReceipt = nil
            memoryReceiptRequestID = nil
            conversationID = UUID().uuidString
            learning.resetConversationPresentation()
            chatError = nil
            chatNotice = nil
            settingsNotice = "已移除此 App 的模型設定與金鑰；訊息草稿保留。"
        } catch {
            settingsError = Self.settingsMessage(error)
        }
    }

    func send(mcp: MCPSession? = nil) {
        if pendingQuote != nil { archive?.reload() }
        guard quoteSourceIsCurrent else { chatError = "引用來源已變更；草稿與引用保留，請重新選取。"; return }
        if hasGeneralAttachment {
            if attachmentRequiresDecision { setAttachmentIssue(.chatAttachmentReselect); return }
            if usesMCP || (learning.available && learning.memory.preferences.useMemory) {
                setAttachmentIssue(.chatAttachmentToolsEnabled); return
            }
            if pdfAttachment != nil { setAttachmentIssue(.chatAttachmentRemoveFirst); return }
            guard attachmentCanSend else { setAttachmentIssue(.chatAttachmentReviewRequired); return }
            guard canSend else { return }
            sendGeneralAttachment()
            return
        }
        guard canSend, let savedSettings else { return }
        if let archive, !entries.isEmpty,
           !archive.state.conversations.contains(where: { $0.id.uuidString == conversationID }) {
            chatError = "原對話已變更或尚未保存；草稿保留，請先確認保存狀態。"
            return
        }
        if let pdfAttachment { sendPDF(pdfAttachment); return }
        let mcpConnection: ((any MCPDiscovering), [MCPTool], [MCPResource])?
        if usesMCP {
            do {
                guard let mcp else { throw MCPError.notInitialized }
                mcpConnection = try mcp.conversationConnection()
            } catch {
                chatError = "請先連線並選取 MCP 工具，或關閉對話的 MCP 選項；草稿已保留。"
                return
            }
        } else { mcpConnection = nil }
        learning.cancelLearning()
        let key: String
        do { key = try repository.key(for: savedSettings) }
        catch {
            hasStoredKey = false
            chatError = "無法讀取金鑰，草稿已保留。請在設定確認或重新儲存金鑰。"
            return
        }
        let draftAtStart = draft
        let quoteAtStart = pendingQuote
        let prompt = ConversationQuote.compose(quoteAtStart, words: draftAtStart)
        // Neither quote markers nor quoted text authorize tools or memory.
        // Evidence is exclusively the words actually entered for this request.
        let utterance = draftAtStart
        let archiveID = UUID(uuidString: conversationID)!
        let destination = archiveDestination
        let archivePrior = archive?.state.conversations.first { $0.id == archiveID }
        let window: ChatContextWindow
        do {
            window = try ChatContextWindow(
                history: entries.map { ModelMessage(role: $0.role, content: $0.content) },
                context: learning.contextMessages(for: utterance), prompt: prompt)
        } catch {
            chatError = ((error as? ChatContextWindowError)?.errorDescription ?? "無法準備本次對話。")
                + "草稿已保留。"
            return
        }
        let messages = window.messages
        let learningGeneration = learning.generation
        let profileState = learning.profile
        let memoryState = learning.memory
        let useLearningTools = learning.available && learning.memory.preferences.useMemory
        let configuration = savedSettings.configuration
        let id = UUID()
        requestID = id
        replyPreview = nil
        isSubmitting = true
        isMCPRun = mcpConnection != nil
        mcpActivity = nil
        mcpSteps = []
        mcpSentCount = 0
        mcpModelCalls = 0; mcpFormatCorrections = 0; mcpPhase = "starting"; updateMCPDiagnostics()
        chatError = nil
        chatNotice = window.omittedTurns == 0 ? nil
            : "本次傳送最近 \(window.retainedTurns) 輪對話、本輪完整訊息及參考資料；較早 \(window.omittedTurns) 輪仍在畫面中，但未傳送。"
        let client = client
        request = Task { [weak self] in
            do {
                let reply: String
                if let (connection, tools, resources) = mcpConnection {
                    reply = try await self?.completeWithMCP(messages: messages, utterance: utterance,
                        profileState: profileState, memoryState: memoryState, generation: learningGeneration,
                        allowsLearning: useLearningTools, configuration: configuration,
                        key: key, client: client, connection: connection, tools: tools, resources: resources, requestID: id) ?? ""
                } else if useLearningTools {
                    reply = try await self?.completeWithProfile(messages: messages, utterance: utterance,
                        state: profileState, memoryState: memoryState, generation: learningGeneration, configuration: configuration,
                        key: key, client: client, requestID: id) ?? ""
                } else {
                    reply = try await self?.completePlain(messages: messages, configuration: configuration,
                        key: key, client: client, requestID: id) ?? ""
                }
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                if mcpConnection != nil { self.mcpPhase = "finished"; self.updateMCPDiagnostics() }
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finish(id: id, error: "模型回傳空白內容，草稿已保留，請重試。")
                    return
                }
                let userEntry = ChatEntry(role: "user", content: prompt)
                let assistantEntry = ChatEntry(role: "assistant", content: reply)
                if let archive = self.archive {
                    self.pendingArchiveSave = nil
                    do {
                        guard let destination else { throw ConversationArchiveError.invalidData }
                        let all = self.entries + [userEntry, assistantEntry]
                        let turns = try stride(from: 0, to: all.count, by: 2).map { index in
                            try ArchivedConversationTurn(userID: all[index].id, assistantID: all[index + 1].id,
                                userText: all[index].content, assistantText: all[index + 1].content, pdf: all[index].pdf)
                        }
                        let record = try ArchivedConversation(id: archiveID, destination: destination,
                            updatedAt: Date(), turns: turns)
                        self.pendingArchiveSave = (record, archivePrior)
                        try archive.save(record, expected: archivePrior)
                        self.pendingArchiveSave = nil
                        self.archiveNotice = nil
                    } catch {
                        self.archiveNotice = Self.archiveSaveFailure
                    }
                }
                self.conversationDestination = destination
                self.replyPreview = nil
                self.entries.append(userEntry)
                self.entries.append(assistantEntry)
                if self.draft == draftAtStart && self.pendingQuote == quoteAtStart {
                    self.draft = ""; self.pendingQuote = nil; self.quoteSource = nil
                }
                self.finish(id: id)
                // Deliver first. A separate, bounded extraction call receives only
                // the user's own utterance, never the model reply or MCP/web content.
                self.learning.rememberAfterReply(utterance: utterance, conversationID: self.conversationID,
                    expectedGeneration: learningGeneration, client: client, configuration: configuration, apiKey: key,
                    preservingToolNotes: self.memoryReceiptRequestID == id ? [self.memoryReceipt?.note].compactMap { $0 } : [])
            } catch {
                guard let self, self.requestID == id else { return }
                if mcpConnection != nil {
                    let category = (error as? MCPConversationError)?.rawValue
                        ?? (error as? MCPChatStop)?.reason.rawValue
                        ?? (error is CancellationError ? "cancelled" : "unknown")
                    self.updateMCPDiagnostics(failure: category)
                }
                // Do not surface provider error bodies/URLs: they may contain secrets.
                let message = (error as? MCPChatStop)?.message
                    ?? (error as? ProfileChatStop)?.message
                    ?? Self.profileFailureMessage(error)
                    ?? Self.modelFailureMessage(error as? MCPConversationError)
                    ?? ((error as? MCPConversationError) == .invalidCommand
                        ? "模型仍未提供可用的單一步驟指令，已停止；草稿與先前工具結果保留。" : nil)
                    ?? (mcpConnection == nil ? "傳送失敗，草稿已保留。請檢查模型設定或網路後重試。"
                        : "MCP 對話未完成，草稿與已收到的工具結果保留；請先確認已送出操作，不會自動重試。")
                if self.memoryReceiptRequestID == id {
                    self.finish(id: id, error: "記憶修改已儲存，但後續模型回覆未完成；請先查看保存結果或撤銷，避免重複修改。草稿保留。")
                } else {
                    self.finish(id: id, error: self.profileReceiptRequestID != id ? message
                        : "個人檔案已儲存，但後續模型回覆未完成；請先查看已保存內容，避免重複修改。草稿保留。")
                }
            }
        }
        deadline = Task { [weak self] in
            let seconds: UInt64 = mcpConnection == nil ? Self.plainRequestDeadlineSeconds : 180
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.request?.cancel()
            if mcpConnection != nil { self.updateMCPDiagnostics(failure: "hostDeadline") }
            if self.memoryReceiptRequestID == id {
                self.finish(id: id, error: "記憶修改已儲存，但後續回覆等待超過 \(seconds) 秒；請先查看保存結果或撤銷。草稿保留。")
            } else {
                self.finish(id: id, error: self.profileReceiptRequestID != id
                    ? "等待超過 \(seconds) 秒，已停止等待；草稿已保留，可重試。"
                    : "個人檔案已儲存，但後續回覆等待超過 \(seconds) 秒；請先查看保存內容。草稿保留。")
            }
        }
    }

    /// A single plain/streaming model request. Tool runners may issue multiple
    /// requests and therefore cannot receive this one-shot attachment.
    private func sendGeneralAttachment() {
        guard (try? repository.load()) == savedSettings else {
            invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentChanged); return
        }
        // Unknown clients may return from cancellation while detached work can
        // still start transport. Do not consume or send through such a client.
        guard client is any LifetimeBoundCompletionChatModelClient else {
            setAttachmentIssue(.chatAttachmentUnavailable); return
        }
        guard let reviewed = attachmentBinding, reviewed == currentAttachmentBinding(),
              let context = attachmentReviewContext(reviewed), attachmentPresenter.state.context == context, let savedSettings,
              let destination = archiveDestination else { setAttachmentIssue(.chatAttachmentChanged); return }
        if let archive, !entries.isEmpty,
           !archive.state.conversations.contains(where: { $0.id.uuidString == conversationID }) {
            setAttachmentIssue(.chatAttachmentChanged); return
        }
        let key: String
        do { key = try repository.key(for: savedSettings) }
        catch { hasStoredKey = false; setAttachmentIssue(.chatAttachmentUnavailable); return }
        let prompt = ConversationQuote.compose(reviewed.quote, words: reviewed.draft)
        let window: ChatContextWindow
        do {
            window = try ChatContextWindow(history: reviewed.history,
                context: learning.contextMessages(for: reviewed.draft), prompt: prompt)
        } catch {
            chatError = ((error as? ChatContextWindowError)?.errorDescription ?? "無法準備本次對話。") + "草稿已保留。"
            return
        }
        // Context collection may itself mutate learning state. Never consume
        // the attachment unless the reviewed snapshot is still current.
        guard reviewed == currentAttachmentBinding() else { invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentChanged); return }
        learning.cancelLearning()
        guard let binding = currentAttachmentBinding() else { invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentChanged); return }
        var beforeCancellation = binding
        beforeCancellation.learningGeneration = reviewed.learningGeneration
        guard beforeCancellation == reviewed else { invalidateAttachmentReview(); setAttachmentIssue(.chatAttachmentChanged); return }
        // Cancelling prior extraction rotates its generation without changing
        // the data disclosed in the already confirmed review.
        attachmentBinding = binding
        let id = UUID(), archiveID = UUID(uuidString: binding.conversationID)!
        let savedConfiguration = savedSettings.configuration
        let configuration = ModelConfiguration(baseURL: savedConfiguration.baseURL, model: savedConfiguration.model,
            maxOutputTokens: savedConfiguration.maxOutputTokens, vision: context.vision)
        let client = client
        requestID = id; attachmentRequestID = id; replyPreview = nil; isSubmitting = true; isMCPRun = false
        attachmentIssue = nil; chatError = nil
        chatNotice = window.omittedTurns == 0 ? nil
            : "本次傳送最近 \(window.retainedTurns) 輪對話、本輪完整訊息及參考資料；較早 \(window.omittedTurns) 輪仍在畫面中，但未傳送。"
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let attachment = try await self.attachmentPresenter.takeConfirmed(context: context)
                await self.attachmentPreflightProbe()
                try self.validateAttachmentStart(binding: binding, context: context, key: key, id: id)
                var messages = window.messages
                guard let final = messages.last, final.role == "user" else { throw ChatAttachmentPresentationError.contextChanged }
                messages[messages.count - 1] = ModelMessage(userText: final.content, attachment: attachment)
                // The independent vault is reread and locked together. Keep
                // this lease until the client returns, including cancellation;
                // async clients may not start transport at their call site.
                let reply: String
                do {
                    let lease = try self.archive?.acquireAttachmentRequestLease(conversationID: archiveID,
                        expected: binding.archivePrior, quoteSource: binding.quoteSource)
                    defer { withExtendedLifetime(lease) {} }
                    reply = try await self.completePlain(messages: messages, configuration: configuration,
                        key: key, client: client, requestID: id, attachmentLease: lease, attachmentRequest: true, validateStart: {
                            self.attachmentClientStartProbe()
                            try self.validateAttachmentStart(binding: binding, context: context, key: key, id: id)
                        })
                    // Do not explicitly release here: a normally finished
                    // consumer can still have a live producer holding this lease.
                    // A busy archive preserves the answer for explicit retry.
                }
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw HTTPChatModelError.invalidResponse
                }
                let user = ChatEntry(role: "user", content: prompt), assistant = ChatEntry(role: "assistant", content: reply)
                if let archive = self.archive {
                    self.pendingArchiveSave = nil
                    do {
                        let all = self.entries + [user, assistant]
                        let turns = try stride(from: 0, to: all.count, by: 2).map { index in
                            try ArchivedConversationTurn(userID: all[index].id, assistantID: all[index + 1].id,
                                userText: all[index].content, assistantText: all[index + 1].content, pdf: all[index].pdf)
                        }
                        let record = try ArchivedConversation(id: archiveID, destination: destination, updatedAt: Date(), turns: turns)
                        self.pendingArchiveSave = (record, binding.archivePrior)
                        try archive.save(record, expected: binding.archivePrior)
                        self.pendingArchiveSave = nil; self.archiveNotice = nil
                    } catch { self.archiveNotice = Self.archiveSaveFailure }
                }
                self.conversationDestination = destination
                self.replyPreview = nil; self.entries.append(user); self.entries.append(assistant)
                if self.draft == binding.draft && self.pendingQuote == binding.quote {
                    self.draft = ""; self.pendingQuote = nil; self.quoteSource = nil
                }
                self.attachmentRequestID = nil; self.attachmentRequiresDecision = false
                if self.attachmentPresenter.state.phase == .consumed { self.attachmentPresenter.discard() }
                self.finish(id: id)
                // No automatic extraction from attachment bytes or model output.
                // The ordinary learning flow remains unchanged for text turns.
            } catch {
                guard self.requestID == id else { return }
                self.attachmentRequestID = nil; self.attachmentRequiresDecision = true
                self.attachmentIssue = .chatAttachmentReselect
                self.finish(id: id, error: AppText.chatAttachmentReselect.traditionalFallback)
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: Self.plainRequestDeadlineSeconds * 1_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.request?.cancel(); self.attachmentRequestID = nil; self.attachmentRequiresDecision = true
            self.attachmentPresenter.discard(); self.attachmentIssue = .chatAttachmentReselect
            self.finish(id: id, error: AppText.chatAttachmentReselect.traditionalFallback)
        }
    }

    /// Native picker callback only. Selecting creates a plan, never reads bytes.
    func selectPDF(url: URL, pages: String? = nil, password: String? = nil) {
        guard !hasGeneralAttachment else { setAttachmentIssue(.chatAttachmentRemoveFirst); return }
        guard !isSubmitting else { return }
        do {
            let selected = try ChatPDFAttachment(userSelectedURL: url, pages: pages, password: password)
            removePDF()
            pdfAttachment = selected
            pdfChanges = selected.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
            chatError = nil
        } catch {
            chatError = (error as? SkillExecutionError)?.errorDescription ?? "無法選取這份 PDF。"
        }
    }

    func removePDF() {
        if pdfAttachment != nil && isSubmitting { cancel() }
        pdfAttachment?.remove(); pdfChanges = nil; pdfAttachment = nil
    }

    func pdfEnteredBackground() {
        guard let attachment = pdfAttachment else { return }
        if isSubmitting { cancel() }
        attachment.stopPreparation()
        attachment.revokeDestination()
    }

    func confirmPDFDestination() {
        guard !isSubmitting, let attachment = pdfAttachment, let destination = archiveDestination else { return }
        do { attachment.confirmDestination(access: try currentPDFModelAccess(), destination: destination); chatError = nil }
        catch { chatError = "無法確認模型服務，請先檢查已儲存的設定。" }
    }

    private func currentPDFModelAccess() throws -> ModelAccess {
        guard let stored = try repository.load(), let savedSettings,
              stored.baseURL == savedSettings.baseURL, stored.model == savedSettings.model,
              stored.credentialAccount == savedSettings.credentialAccount else { throw DocumentQueryError.contextChanged }
        return try modelAccess()
    }

    private func sendPDF(_ attachment: ChatPDFAttachment) {
        guard !usesMCP, let source = attachment.source else { return }
        let draftAtStart = draft
        let quoteAtStart = pendingQuote
        let prompt = ConversationQuote.compose(quoteAtStart, words: draftAtStart)
        let archiveID = UUID(uuidString: conversationID)!
        let archivePrior = archive?.state.conversations.first { $0.id == archiveID }
        do {
            let access = try currentPDFModelAccess()
            try attachment.validate(access: access, destination: archiveDestination)
            guard let destination = archiveDestination else { throw DocumentQueryError.contextChanged }
            let runtime = try DocumentQueryRuntime(source: source, question: prompt)
            learning.cancelLearning()
            let references = try learning.captureRunReferences(goal: draftAtStart, capabilities: DocumentQueryRuntime.referenceCapabilities)
            let id = UUID(); requestID = id; replyPreview = nil; chatError = nil
            isMCPRun = false; isSubmitting = true
            #if DEBUG
            pdfModelRequestEvents = 0
            #endif
            chatNotice = nil // The attached card already displays the disclosure; keep the composer reachable.
            references.onRevoke = { [weak self] in
                guard let self, self.requestID == id else { return }
                self.cancel(); self.chatError = "本次參考資料已撤銷，PDF 查詢已停止；請重新確認後再傳送。"
            }
            request = Task { [weak self] in
                defer { references.onRevoke = nil; references.revoke() }
                do {
                    let outcome = try await runtime.run(client: access.client, configuration: access.configuration,
                        apiKey: access.key, references: references.references, validateContext: { [weak self] in
                            guard let self, self.requestID == id, self.pdfAttachment?.id == attachment.id,
                                  self.draft == draftAtStart, self.pendingQuote == quoteAtStart,
                                  !Task.isCancelled else { throw DocumentQueryError.contextChanged }
                            try references.check()
                            try attachment.validate(access: self.currentPDFModelAccess(), destination: self.archiveDestination)
                        }, onEvent: { [weak self] event in
                            #if DEBUG
                            guard let self, self.requestID == id else { return }
                            if case .requestingModel(let count) = event { self.pdfModelRequestEvents = count }
                            #endif
                        })
                    guard let self, self.requestID == id else { return }
                    guard self.pdfAttachment?.id == attachment.id, self.draft == draftAtStart,
                          self.pendingQuote == quoteAtStart, !Task.isCancelled
                    else { throw DocumentQueryError.contextChanged }
                    try references.check()
                    try attachment.validate(access: self.currentPDFModelAccess(), destination: self.archiveDestination)
                    guard case .completed(let result) = outcome else {
                        self.finish(id: id, error: "模型未完成 PDF 查詢；問題與擷取文字保留，未保存完成問答。")
                        return
                    }
                    let evidence = try ChatPDFAttachment.archive(result)
                    let user = ChatEntry(role: "user", content: prompt, pdf: evidence)
                    let assistant = ChatEntry(role: "assistant", content: result.answer)
                    if let archive = self.archive {
                        self.pendingArchiveSave = nil
                        do {
                            let all = self.entries + [user, assistant]
                            let turns = try stride(from: 0, to: all.count, by: 2).map { i in
                                try ArchivedConversationTurn(userID: all[i].id, assistantID: all[i + 1].id,
                                    userText: all[i].content, assistantText: all[i + 1].content, pdf: all[i].pdf)
                            }
                            let record = try ArchivedConversation(id: archiveID, destination: destination, updatedAt: Date(), turns: turns)
                            self.pendingArchiveSave = (record, archivePrior)
                            try archive.save(record, expected: archivePrior)
                            self.pendingArchiveSave = nil; self.archiveNotice = nil
                        } catch { self.archiveNotice = Self.archiveSaveFailure }
                    }
                    self.conversationDestination = destination
                    self.entries.append(user); self.entries.append(assistant)
                    if self.draft == draftAtStart && self.pendingQuote == quoteAtStart {
                        self.draft = ""; self.pendingQuote = nil; self.quoteSource = nil
                    }
                    self.finish(id: id)
                    self.removePDF()
                    // Deliberately no rememberAfterReply: source text is not a user utterance.
                } catch {
                    guard let self, self.requestID == id else { return }
                    if (error as? DocumentQueryError) == .contextChanged { attachment.revokeDestination() }
                    self.finish(id: id, error: (error as? DocumentQueryError)?.errorDescription
                        ?? "PDF 查詢未完成；問題與擷取文字保留，未保存完成問答。")
                }
            }
        } catch {
            attachment.revokeDestination()
            chatError = (error as? DocumentQueryError)?.errorDescription ?? "無法開始 PDF 查詢；請確認目的服務與來源。"
        }
    }

    private func completePlain(messages: [ModelMessage], configuration: ModelConfiguration,
                               key: String, client: any ChatModelClient, requestID id: UUID,
                               attachmentLease: EncryptedLearningFile.ExclusiveLease? = nil, attachmentRequest: Bool = false,
                               validateStart: () throws -> Void = {}) async throws -> String {
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        // Runs on the main actor after entering this async method and directly
        // before initiating either client path.
        try validateStart()
        guard let streaming = client as? any StreamingChatModelClient else {
            return try await client.complete(messages: messages, configuration: configuration, apiKey: key)
        }
        let deltas: AsyncThrowingStream<String, Error>
        if let lease = attachmentLease {
            // A generic stream can terminate its consumer while an unstructured
            // producer is still starting transport. Require an explicit producer
            // lifetime contract, otherwise make one complete request instead.
            guard let retaining = streaming as? any LifetimeRetainingStreamingChatModelClient else {
                return try await client.complete(messages: messages, configuration: configuration, apiKey: key)
            }
            deltas = retaining.stream(messages: messages, configuration: configuration, apiKey: key, retaining: lease)
        } else if attachmentRequest {
            // No archive lease exists to carry into an unstructured producer.
            return try await client.complete(messages: messages, configuration: configuration, apiKey: key)
        } else {
            deltas = streaming.stream(messages: messages, configuration: configuration, apiKey: key)
        }
        var text = "", bytes = 0
        for try await delta in deltas {
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }
            guard delta.utf8.count <= ChatReplyPreview.maximumUTF8Bytes - bytes else {
                throw HTTPChatModelError.responseTooLarge
            }
            guard !delta.isEmpty else { continue }
            bytes += delta.utf8.count; text += delta
            replyPreview = ChatReplyPreview(id: id, text: text, phase: .receiving)
        }
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        return text
    }

    private func stopPreview(id: UUID, phase: ChatReplyPreview.Phase) {
        guard var preview = replyPreview, preview.id == id, preview.phase == .receiving else { return }
        preview.phase = phase; replyPreview = preview
    }

    private static func modelFailureMessage(_ error: MCPConversationError?) -> String? {
        let reason: String
        switch error {
        case .modelAuthenticationRejected:
            reason = "模型服務拒絕驗證，請檢查模型金鑰與存取權限。"
        case .modelRateLimited:
            reason = "模型服務目前限制請求，請稍後再試。"
        case .modelServiceUnavailable:
            reason = "模型服務暫時無法處理請求，請稍後再試。"
        case .modelRequestRejected, .modelHTTPRejected:
            reason = "模型服務拒絕這次請求，請檢查服務與模型設定。"
        case .modelTimedOut:
            reason = "等待模型回覆已逾時。"
        case .modelTransportFailed:
            reason = "無法連線至模型服務，請檢查網路。"
        case .localUnavailable:
            reason = "本次對話未啟用記憶與個人檔案工具，修改要求已停止。"
        case .localLeaseExpired:
            reason = "這次記憶工具操作已失效，修改要求已停止。"
        case .invalidLocalResult:
            reason = "本機記憶工具未傳回完整結果，對話已停止。"
        default: return nil
        }
        return reason + "草稿與已收到的工具結果保留；沒有自動重送操作。"
    }

    func cancel() {
        learning.cancelLearning()
        let cancelledAttachment = attachmentRequestID != nil
        if attachmentRequestID != nil {
            attachmentRequiresDecision = true
            attachmentPresenter.discard()
            setAttachmentIssue(.chatAttachmentReselect)
            attachmentRequestID = nil
        }
        guard let id = requestID else { return }
        pdfAttachment?.revokeDestination()
        if isMCPRun { updateMCPDiagnostics(failure: "cancelled") }
        stopPreview(id: id, phase: .cancelled)
        request?.cancel()
        finish(id: id, error: cancelledAttachment ? AppText.chatAttachmentReselect.traditionalFallback : nil)
        chatNotice = "已取消等待，草稿已保留。伺服器可能已收到請求。"
    }

    func cancelMCP() {
        guard isMCPRun else { return }
        cancel()
    }

    /// Pending profile and memory reviews are invalidated immediately. Structured
    /// ordinary-chat responses also recheck learning state before publication.
    func invalidateProfileReview() {
        guard pendingProfileReview != nil || pendingMemoryReview != nil else { return }
        cancel()
    }

    private func completeWithProfile(messages: [ModelMessage], utterance: String,
                                     state: UserProfileState, memoryState: MemoryState, generation: UUID,
                                     configuration: ModelConfiguration, key: String,
                                     client: any ChatModelClient, requestID: UUID) async throws -> String {
        let flow = try UserProfileChatFlow(messages: messages)
        var memoryRun = MemoryToolRun(state: memoryState, utterances: [utterance])
        var expectedProfileRevision = state.revision
        var expectedMemoryRevision = memoryState.revision
        defer { flow.cancel() }
        while true {
            let step = try await flow.advance(client: client, configuration: configuration, apiKey: key,
                                              validateState: { [weak self] in
                guard let self, self.requestID == requestID else { throw CancellationError() }
                try Task.checkCancellation()
                guard self.learning.available, self.learning.memory.preferences.useMemory,
                      self.learning.generation == generation,
                      self.learning.profile.revision == expectedProfileRevision,
                      self.learning.memory.revision == expectedMemoryRevision else {
                    self.replyPreview = nil
                    throw UserProfileToolError.staleRevision
                }
            }) { [weak self] answer in
                guard let self, self.requestID == requestID, !Task.isCancelled else { return }
                self.replyPreview = answer.map { ChatReplyPreview(id: requestID, text: $0, phase: .receiving) }
            }
            try Task.checkCancellation()
            guard self.requestID == requestID else { throw CancellationError() }
            switch step {
            case .answer(let answer): return answer
            case .proposedEdit(let arguments):
                guard learning.available, learning.memory.preferences.useMemory,
                      learning.generation == generation, learning.profile.revision == state.revision else {
                    throw UserProfileToolError.staleRevision
                }
                // Only the actual draft sent for this run is evidence. Context,
                // old messages and model replies cannot authorize an edit.
                let proposal = try UserProfileToolRequest.parse(arguments).prepare(state: state, utterances: [utterance])
                let approved = await approveProfile(proposal, requestID: requestID)
                try Task.checkCancellation()
                guard self.requestID == requestID else { throw CancellationError() }
                guard approved else { throw ProfileChatStop.declined }
                try flow.validateReview()
                let receipt = try learning.commitProfileTool(proposal, expectedGeneration: generation)
                profileReceipt = receipt // Retained even if the next model call fails.
                profileReceiptRequestID = requestID
                expectedProfileRevision = learning.profile.revision
                try flow.recordCommitted(entryID: receipt.id)
            case .memorySearch(let arguments):
                try validateMemoryRun(memoryRun, generation: generation)
                let found = try memoryRun.search(argumentsJSON: arguments)
                try flow.recordMemorySearchResult(found.resultJSON())
            case .proposedMemoryChange(let toolName, let arguments):
                try validateMemoryRun(memoryRun, generation: generation)
                let review = try memoryRun.prepare(toolName: toolName, argumentsJSON: arguments)
                let approved = await approveMemory(review, requestID: requestID)
                try Task.checkCancellation()
                guard self.requestID == requestID else { throw CancellationError() }
                guard approved else { throw MemoryChatStop.declined }
                try flow.validateReview()
                let receipt = try learning.commitMemoryTool(review, expectedGeneration: generation,
                    conversationID: conversationID)
                memoryReceipt = receipt
                memoryReceiptRequestID = requestID
                expectedMemoryRevision = learning.memory.revision
                try flow.recordMemoryCommitted(toolName: toolName, resultJSON: receipt.resultJSON())
            }
        }
    }

    private func validateMemoryRun(_ run: MemoryToolRun, generation: UUID) throws {
        guard learning.available, learning.memory.preferences.useMemory,
              learning.generation == generation, learning.memory.revision == run.baseRevision else {
            throw MemoryToolError.staleRevision
        }
    }

    func resolveMemoryReview(id: UUID, approved: Bool) {
        guard pendingMemoryReview?.id == id else { return }
        pendingMemoryReview = nil
        let continuation = memoryApprovalContinuation
        memoryApprovalContinuation = nil
        continuation?.resume(returning: approved)
    }

    private func approveMemory(_ review: MemoryToolReview, requestID: UUID) async -> Bool {
        guard self.requestID == requestID, !Task.isCancelled else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard self.requestID == requestID, !Task.isCancelled else {
                    continuation.resume(returning: false); return
                }
                memoryApprovalContinuation = continuation
                pendingMemoryReview = review
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == requestID, let review = self.pendingMemoryReview else { return }
                self.resolveMemoryReview(id: review.id, approved: false)
            }
        }
    }

    func resolveProfileReview(id: UUID, approved: Bool) {
        guard pendingProfileReview?.id == id else { return }
        pendingProfileReview = nil
        let continuation = profileApprovalContinuation
        profileApprovalContinuation = nil
        continuation?.resume(returning: approved)
    }

    private func approveProfile(_ review: UserProfileToolReview, requestID: UUID) async -> Bool {
        guard self.requestID == requestID, !Task.isCancelled else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard self.requestID == requestID, !Task.isCancelled else {
                    continuation.resume(returning: false); return
                }
                profileApprovalContinuation = continuation
                pendingProfileReview = review
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == requestID, let proposal = self.pendingProfileReview else { return }
                self.resolveProfileReview(id: proposal.id, approved: false)
            }
        }
    }

    private static func profileFailureMessage(_ error: Error) -> String? {
        if error is LearningFileError {
            return "學習資料無法儲存，這次修改未發布；原有資料與草稿保留，請確認裝置儲存狀態後再試。"
        }
        if let stopped = error as? MemoryChatStop { return stopped.message }
        if error is MemoryToolError || error is MemoryError {
            return "記憶工具未通過來源、目標或資料狀態檢查，已停止；草稿保留。已完成的儲存會另外顯示。"
        }
        if error is UserProfileToolError || error is UserProfileError || error is UserProfileChatError {
            return "個人檔案工具未通過檢查或已超過執行限制，已停止；草稿保留。已完成的儲存會另外顯示。"
        }
        return nil
    }

    private func completeWithMCP(messages: [ModelMessage], utterance: String,
                                 profileState: UserProfileState, memoryState: MemoryState,
                                 generation: UUID, allowsLearning: Bool, configuration: ModelConfiguration,
                                 key: String, client: any ChatModelClient,
                                 connection: any MCPDiscovering, tools: [MCPTool], resources: [MCPResource], requestID: UUID) async throws -> String {
        let turn = MCPLearningTurn(profile: profileState, memory: memoryState,
                                   utterance: utterance, generation: generation)
        let local: MCPLocalHandler?
        if allowsLearning {
            local = { [weak self] proposal, lease in
                guard let self else { throw CancellationError() }
                return try await self.performMCPLocal(proposal, lease: lease, turn: turn, requestID: requestID)
            }
        } else { local = nil }
        let result = try await MCPConversationRunner(client: client).run(
            messages: messages, configuration: configuration, apiKey: key,
            tools: tools, resources: resources, executor: connection,
            approve: { [weak self] proposal in
                switch proposal.action {
                case .callTool(let name, let arguments):
                    return await self?.approveMCP(name: name, arguments: arguments, requestID: requestID) ?? false
                case .readResource(let uri):
                    return await self?.approveMCP(name: "讀取 MCP 資源", arguments: .object(["uri": .string(uri)]), requestID: requestID) ?? false
                }
            }, onEvent: { [weak self] event in
                await self?.receiveMCP(event, requestID: requestID)
            }, handleLocal: local)
        guard result.stopReason == .finished, let answer = result.answer else { throw MCPChatStop(reason: result.stopReason) }
        return answer
    }

    /// Local learning and the remote MCP connection are separate capabilities.
    /// Every proposal is validated against this turn's captured user utterance;
    /// remote catalogs/results cannot supply that authority or replace its IDs.
    private func performMCPLocal(_ proposal: MCPLocalProposal, lease: MCPLocalLease,
                                 turn: MCPLearningTurn, requestID: UUID) async throws -> MCPLocalOutcome {
        try lease.check()
        guard self.requestID == requestID else { throw CancellationError() }
        switch proposal.action {
        case .memorySearch:
            try validateMemoryRun(turn.memory, generation: turn.generation)
            let result = try turn.memory.search(argumentsJSON: proposal.argumentsJSON)
            return .searchResult(json: try result.resultJSON())
        case .profileEdit:
            guard learning.available, learning.memory.preferences.useMemory,
                  learning.generation == turn.generation, learning.profile.revision == turn.profile.revision else {
                throw UserProfileToolError.staleRevision
            }
            let review = try UserProfileToolRequest.parse(proposal.argumentsJSON)
                .prepare(state: turn.profile, utterances: [turn.utterance])
            let approved = await approveProfile(review, requestID: requestID)
            // No suspension between this lease/request check and the store's
            // generation/master/revision checks plus atomic write.
            try lease.check()
            guard self.requestID == requestID else { throw CancellationError() }
            guard approved else { return .declined }
            let receipt = try learning.commitProfileTool(review, expectedGeneration: turn.generation)
            profileReceipt = receipt
            profileReceiptRequestID = requestID
            let data = try JSONEncoder().encode(receipt)
            return .committedReceipt(json: String(decoding: data, as: UTF8.self))
        case .memorySave, .memoryEdit:
            try validateMemoryRun(turn.memory, generation: turn.generation)
            let review = try turn.memory.prepare(toolName: proposal.action.rawValue,
                                                 argumentsJSON: proposal.argumentsJSON)
            let approved = await approveMemory(review, requestID: requestID)
            try lease.check()
            guard self.requestID == requestID else { throw CancellationError() }
            guard approved else { return .declined }
            let receipt = try learning.commitMemoryTool(review, expectedGeneration: turn.generation,
                                                        conversationID: conversationID)
            memoryReceipt = receipt
            memoryReceiptRequestID = requestID
            return .committedReceipt(json: try receipt.resultJSON())
        }
    }

    private func receiveMCP(_ event: MCPConversationEvent, requestID: UUID) {
        guard self.requestID == requestID else { return }
        switch event {
        case .requestingModel(let count): mcpPhase = "requestingModel"; mcpModelCalls = count
        case .correctingCommand: mcpPhase = "correctingCommand"; mcpFormatCorrections += 1
        case .awaitingApproval: mcpPhase = "awaitingApproval"
        case .executing: mcpPhase = "executing"; mcpSentCount += 1
        case .completed(let step): mcpPhase = "receivedResult"; mcpSteps.append(step)
        }
        mcpActivity = "MCP 嘗試呼叫 \(mcpSentCount) 次；已收到 \(mcpSteps.count) 次結果；工具錯誤 \(mcpSteps.filter(\.isError).count) 次。"
        updateMCPDiagnostics()
    }

    /// Test-only, fixed enums and counters. Never include proposals, tool
    /// outputs, model text, endpoint, or underlying error descriptions.
    private func updateMCPDiagnostics(failure: String = "none") {
        #if DEBUG
        guard isUITestMode || ProcessInfo.processInfo.arguments.contains("-LiveMCPConversationUITest") else { return }
        mcpDiagnostics = "phase=\(mcpPhase);modelCalls=\(mcpModelCalls);formatCorrections=\(mcpFormatCorrections);attempts=\(mcpSentCount);results=\(mcpSteps.count);toolErrors=\(mcpSteps.filter(\.isError).count);failure=\(failure)"
        #endif
    }

    func resolveMCPApproval(id: UUID, approved: Bool) {
        guard pendingMCPApproval?.id == id else { return }
        pendingMCPApproval = nil
        let continuation = mcpApprovalContinuation
        mcpApprovalContinuation = nil
        continuation?.resume(returning: approved)
    }

    private func approveMCP(name: String, arguments: JSONValue, requestID: UUID) async -> Bool {
        guard self.requestID == requestID, !Task.isCancelled else { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard self.requestID == requestID, !Task.isCancelled else {
                    continuation.resume(returning: false); return
                }
                mcpApprovalContinuation = continuation
                pendingMCPApproval = MCPApprovalRequest(name: name, arguments: arguments)
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.requestID == requestID, let proposal = self.pendingMCPApproval else { return }
                self.resolveMCPApproval(id: proposal.id, approved: false)
            }
        }
    }

    func newConversation() {
        guard !isSubmitting, pendingQuote == nil, !hasGeneralAttachment else { return }
        removePDF()
        learning.resetConversationPresentation()
        entries = []; conversationID = UUID().uuidString
        replyPreview = nil
        pendingQuote = nil
        quoteSource = nil
        conversationDestination = nil; archiveNotice = nil; pendingArchiveSave = nil
        mcpActivity = nil; mcpSteps = []; mcpSentCount = 0
        mcpDiagnostics = nil
        profileReceipt = nil
        profileReceiptRequestID = nil
        memoryReceipt = nil
        memoryReceiptRequestID = nil
        chatError = nil; chatNotice = "已開啟新對話；已確認的記憶與技能保留。"
    }

    private func finish(id: UUID, error: String? = nil) {
        guard requestID == id else { return }
        if error != nil { stopPreview(id: id, phase: .failed) }
        if let pending = pendingMCPApproval { resolveMCPApproval(id: pending.id, approved: false) }
        if let pending = pendingProfileReview { resolveProfileReview(id: pending.id, approved: false) }
        if let pending = pendingMemoryReview { resolveMemoryReview(id: pending.id, approved: false) }
        requestID = nil
        isSubmitting = false
        isMCPRun = false
        request = nil
        deadline?.cancel()
        deadline = nil
        chatError = error
    }

    private static func liveRepository() -> ModelSettingsRepository {
        ModelSettingsRepository(defaults: .standard, credentials: KeychainModelCredentials(service: "io.woowtech.assistant.model-credentials.v1"))
    }

    private static func settingsMessage(_ error: Error) -> String {
        (error as? ModelSettingsError)?.errorDescription ?? "無法讀取或儲存模型設定，請移除設定後重新填寫。"
    }
}

/// Mutable search candidates belong to exactly one MainActor conversation.
/// Captured snapshots are never refreshed from model or remote-tool output.
@MainActor private final class MCPLearningTurn {
    let profile: UserProfileState
    var memory: MemoryToolRun
    let utterance: String
    let generation: UUID

    init(profile: UserProfileState, memory: MemoryState, utterance: String, generation: UUID) {
        self.profile = profile
        self.memory = MemoryToolRun(state: memory, utterances: [utterance])
        self.utterance = utterance
        self.generation = generation
    }
}

private enum ProfileChatStop: Error {
    case declined
    var message: String { "你已拒絕這次個人檔案修改；尚未儲存，訊息草稿已保留。" }
}

private enum MemoryChatStop: Error {
    case declined
    var message: String { "你已拒絕這次記憶修改；尚未儲存，訊息草稿已保留。" }
}

private struct MCPChatStop: Error {
    let reason: MCPConversationStopReason
    var message: String {
        switch reason {
        case .approvalDenied: return "你已拒絕這次呼叫，MCP 對話已停止；草稿與先前工具結果保留。"
        case .toolError: return "工具回報錯誤，已停止；請檢視工具結果。草稿保留，不會自動重試。"
        case .localCallLimit: return "本次對話的記憶搜尋或修改額度已用完，已停止；草稿與先前結果保留。"
        default: return "已達 MCP 執行限制或偵測到重複呼叫；草稿與已收到的工具結果保留。"
        }
    }
}
