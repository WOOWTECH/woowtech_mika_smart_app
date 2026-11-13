import AssistantModels
import AssistantMCP
import AssistantMemory
import AssistantPersistence
import AssistantSkills
import Combine
import Foundation

struct ModelAccess {
    let client: any ChatModelClient
    let configuration: ModelConfiguration
    let key: String
    /// Provider, model and Keychain item. Running work compares this, never
    /// the key, to notice that the settings changed under it.
    let identity: ModelAccessIdentity
}

/// What the AI-sharing consent (App Review 5.1.2(i)) names: the service and
/// the host that would receive the user's content, and what asks for it.
struct ModelConsentPrompt: Identifiable, Equatable {
    enum Purpose: Equatable {
        /// Saving the provider that becomes the first main model.
        case save
        /// Making another provider's model the main model.
        case switchMain
        /// The first send to a main model set up before the consent existed.
        case send
    }
    let id = UUID()
    let providerName: String
    /// The host, with its port when it is not 443.
    let host: String
    let purpose: Purpose

    init(name: String, baseURL: URL, purpose: Purpose) {
        providerName = name
        let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        host = (parts?.host ?? baseURL.absoluteString) + (parts?.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? "")
        self.purpose = purpose
    }

    init(provider: ModelProvider, purpose: Purpose) {
        self.init(name: provider.name, baseURL: provider.baseURL, purpose: purpose)
    }
}

/// Everything the App can send to the main model's provider, in the order the
/// AI-sharing consent lists it. This is the one list: the privacy policy uses
/// the same items and words (AppText consent.item.*).
enum ModelSharedContent: String, CaseIterable {
    case chat, attachments, images, profile, memory, skills, memoryOrganizing, web, researchJudgment, mcp

    var text: AppText {
        switch self {
        case .chat: return .consentItemChat
        case .attachments: return .consentItemAttachments
        case .images: return .consentItemImages
        case .profile: return .consentItemProfile
        case .memory: return .consentItemMemory
        case .skills: return .consentItemSkills
        case .memoryOrganizing: return .consentItemMemoryOrganizing
        case .web: return .consentItemWeb
        case .researchJudgment: return .consentItemResearchJudgment
        case .mcp: return .consentItemMCP
        }
    }
}

struct ChatEntry: Identifiable {
    let id: UUID
    let role: String
    /// What the model saw in later turns, including one "附件:" line per attachment.
    let content: String
    let pdf: ArchivedPDFAnswer?
    let attachments: [ChatAttachmentItem]
    init(id: UUID = UUID(), role: String, content: String, pdf: ArchivedPDFAnswer? = nil,
         attachments: [ChatAttachmentItem] = []) {
        self.id = id; self.role = role; self.content = content
        self.pdf = pdf
        self.attachments = attachments
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

/// The runner publishes .executing before entering its executor. Reacquire the
/// exact chat fence *after* that callback and hold the cooperative lock until
/// the real executor returns. Cancellation of the caller does not release the
/// lock while an executor that ignores cancellation is still running.
private struct ContextFencedMCPExecutor: MCPConversationExecuting {
    let executor: any MCPDiscovering
    let fence: ChatContextFence

    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        let lease = try await MainActor.run { try fence.acquire() }
        defer { lease.release() }
        try Task.checkCancellation()
        return try await executor.callAuthorizedTool(name: name, arguments: arguments)
    }

    func readResource(uri: String) async throws -> JSONValue {
        let lease = try await MainActor.run { try fence.acquire() }
        defer { lease.release() }
        try Task.checkCancellation()
        return try await executor.readResource(uri: uri)
    }
}

/// Why a typed message cannot start yet. Mirrors the Android store build's
/// chat card ("還不能開始任務／還缺:…") so a tap on send is never silent.
enum ChatSendBlocker: Equatable {
    case noModel
}

/// Which messages the long-press menu can quote, branch from or ask again
/// from right now (Android MessageMenu shows those entries only when they
/// work). Built once per transcript render; copy and select text need none.
struct ChatMessageActionTargets: Equatable {
    static let none = ChatMessageActionTargets(saved: [], replies: [], questions: [])
    /// Saved messages of the conversation on screen; quoting works on these.
    let saved: Set<UUID>
    /// Finished, saved replies to branch from (從這裡分支).
    let replies: Set<UUID>
    /// Your saved messages to ask again from (從這裡重新問).
    let questions: Set<UUID>
}

/// A plain chat request's model failure, worded like the Android store
/// build's ModelErrorCopy.failure (呼叫模型失敗：…). Provider error bodies are
/// never shown, so the reason comes from the HTTP status alone; failures it
/// cannot name keep the generic message.
enum ChatModelFailure: Equatable {
    case auth, quota, rateLimited, notFound, network, streamCut, unreadable
    case server(Int), status(Int)

    init?(_ error: Error) {
        guard let error = error as? HTTPChatModelError else { return nil }
        switch error {
        case .httpStatus(401), .httpStatus(403): self = .auth
        case .httpStatus(402): self = .quota
        case .httpStatus(404): self = .notFound
        case .httpStatus(429): self = .rateLimited
        case .httpStatus(let status) where (500...599).contains(status): self = .server(status)
        case .httpStatus(let status) where (400...499).contains(status): self = .status(status)
        case .transportFailure: self = .network
        case .incompleteResponse: self = .streamCut
        case .invalidResponse: self = .unreadable
        default: return nil
        }
    }

    var text: AppText {
        switch self {
        case .auth: return .chatModelFailedAuth
        case .quota: return .chatModelFailedQuota
        case .rateLimited: return .chatModelFailedRateLimited
        case .notFound: return .chatModelFailedNotFound
        case .network: return .chatModelFailedNetwork
        case .streamCut: return .chatModelFailedStreamCut
        case .unreadable: return .chatModelFailedUnreadable
        case .server(let status): return .chatModelFailedServer(status: status)
        case .status(let status): return .chatModelFailedStatus(status: status)
        }
    }

    /// The Traditional Chinese sentence, for chatError and its existing readers.
    var traditionalText: String { String(format: text.traditionalFallback, arguments: text.arguments) }
}

/// What 從這裡分支 or 從這裡重新問 did; the chat view says it in a toast
/// like the Android store build.
enum ChatBranchOutcome: Equatable {
    /// A new branch conversation is open (已建立分支).
    case created
    /// As created, but the message's attachments stay behind (附件需要重新加入).
    case needsReattach
    /// The first message asked again: a new conversation with its words back.
    case startedOver
    /// Busy, changed or unsaved conversation, or a failed save (沒能建立分支).
    case failed
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
    @Published var draft = ""
    @Published private(set) var pendingQuote: ConversationQuote.Quote?
    private var quoteSource: ArchivedConversation?
    @Published var baseURLDraft = ""
    @Published var modelDraft = ""
    @Published var keyDraft = ""
    @Published private(set) var entries: [ChatEntry] = []
    @Published private(set) var replyPreview: ChatReplyPreview?
    /// Photos and files waiting for the next prompt, in the order picked (Android's tray).
    @Published private(set) var pendingAttachments: [ChatAttachmentItem] = []
    /// While picked files are copied, "+" and send wait, as on Android.
    @Published private(set) var isAddingAttachments = false
    @Published var attachmentNotice: ChatAttachmentNotice?
    let attachmentStore: ChatAttachmentStore
    private var attachmentImport: Task<Void, Never>?
    @Published private(set) var savedSettings: SavedModelSettings?
    @Published private(set) var hasStoredKey = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var chatError: String? {
        didSet { chatErrorText = nil }
    }
    /// chatError in the interface language, when it is a named model failure.
    @Published private(set) var chatErrorText: AppText?
    @Published private(set) var chatNotice: String?
    /// Shown after a send attempt that lacks a prerequisite; closed content only.
    @Published private(set) var shownSendBlocker: ChatSendBlocker?
    @Published private(set) var settingsError: String?
    @Published private(set) var settingsNotice: String?
    /// The provider list, roles and consent behind Settings › 模型; empty
    /// before the first provider.
    @Published private(set) var providerDocument = ModelProvidersDocument()
    /// Providers whose key item exists; nil when the Keychain could not list them.
    @Published private(set) var keyedProviders: Set<UUID>?
    /// What the last change in Settings › 模型 did, in the interface language.
    @Published private(set) var providerNotice: AppText?
    /// The consent asked before a send to a provider never agreed to.
    @Published private(set) var pendingSendConsent: ModelConsentPrompt?
    private var consentMCP: MCPSession?
    @Published var usesMCP = false
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
    private var isMCPRun = false
    private var mcpSentCount = 0

    #if DEBUG
    #endif
    let isUITestMode: Bool
    private let repository: ModelSettingsRepository
    /// Shares the exact repository used by this session, including UI-test
    /// isolation. The provider choice remains unavailable in the public UI.
    var voiceModelRepository: ModelSettingsRepository { repository }
    private let client: any ChatModelClient
    private let assistantQuoteText: @MainActor (String) -> String
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var requestID: UUID?
    /// Read-only completion handle for joining an already captured task after cancellation.
    var capturedArchiveRequest: Task<Void, Never>? { request }

    init() {
        assistantQuoteText = Self.plainAssistantQuote
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let streamFixture: UITestChatStreamingConfiguration?
        do {
            streamFixture = try UITestChatStreamingConfiguration.resolve(arguments: arguments)
        }
        catch { preconditionFailure("Chat UI fixture requires one isolated UI test mode and UUID namespace; no Live mode") }
        #endif
        learning = LearningStore()
        archive = ConversationArchiveStore()
        attachmentStore = ChatAttachmentStore.live()
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
            if let streamFixture { client = UITestStreamingChatModelClient(configuration: streamFixture) }
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
         archive: ConversationArchiveStore? = nil, attachmentStore: ChatAttachmentStore? = nil,
         assistantQuoteText: @escaping @MainActor (String) -> String = ChatSession.plainAssistantQuote) {
        self.learning = learning
        self.archive = archive
        // Hosted tests get a throwaway folder, never the user's attachments.
        self.attachmentStore = attachmentStore ?? ChatAttachmentStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachments-" + UUID().uuidString, isDirectory: true))
        self.repository = repository
        self.client = client
        self.assistantQuoteText = assistantQuoteText
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
        // Keys no provider uses: an interrupted save, or the v1 setting that
        // could not be read. A locked Keychain waits for the next launch.
        _ = try? repository.sweepOrphanedCredentials()
        reloadProviders()
    }

    /// Reads the provider list for Settings › 模型 again, and which providers
    /// still have their key (a restored device has the list but no keys).
    func reloadProviders() {
        let document = (try? repository.document()) ?? nil
        providerDocument = document ?? ModelProvidersDocument()
        keyedProviders = document.flatMap { repository.providersWithKeys(in: $0) }
    }

    /// The main model's provider was never agreed to (App Review 5.1.2(i)):
    /// a setting from before the consent existed. Nothing is sent to it until
    /// the user agrees.
    var mainNeedsConsent: Bool { savedSettings?.providerID != nil && providerDocument.mainNeedsConsent }

    /// What the consent screen names for the main model's provider.
    func consentPrompt(forProvider id: UUID, purpose: ModelConsentPrompt.Purpose) -> ModelConsentPrompt? {
        providerDocument.provider(id: id).map { ModelConsentPrompt(provider: $0, purpose: purpose) }
    }

    var canSend: Bool {
        savedSettings != nil && hasStoredKey && !isSubmitting && !isAddingAttachments
            && quoteSourceIsCurrent
            && (conversationDestination == nil || conversationDestination == archiveDestination)
            && hasSomethingToSend
    }

    /// Words, attachments, or both: on Android a photo alone can start a task.
    private var hasSomethingToSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    /// Whether the send key accepts a tap. Like the Android store build, a
    /// non-empty draft or any attachment is enough; `attemptSend` explains
    /// whatever is still missing. Picked files still being copied make it wait.
    var canAttemptSend: Bool {
        !isSubmitting && !isAddingAttachments && hasSomethingToSend
    }

    /// Send when every guard passes; otherwise say why and keep the draft.
    /// A main model whose provider was never agreed to asks first.
    func attemptSend(mcp: MCPSession? = nil) {
        guard canAttemptSend else { return }
        guard savedSettings != nil, hasStoredKey else { shownSendBlocker = .noModel; return }
        shownSendBlocker = nil
        guard conversationDestination == nil || conversationDestination == archiveDestination else {
            chatError = "這段對話使用的模型設定已變更；請開新對話後再傳送，草稿已保留。"
            return
        }
        if mainNeedsConsent, let provider = savedSettings?.providerID {
            consentMCP = mcp
            pendingSendConsent = consentPrompt(forProvider: provider, purpose: .send)
            if pendingSendConsent != nil { return }
        }
        send(mcp: mcp)
    }

    /// The answer to the consent asked before a send. Declining sends
    /// nothing and keeps the draft; agreeing records it and sends.
    func resolveSendConsent(agreed: Bool) {
        guard let prompt = pendingSendConsent else { return }
        let mcp = consentMCP
        pendingSendConsent = nil; consentMCP = nil
        guard agreed else {
            let text = AppText.chatConsentDeclined(provider: prompt.providerName)
            chatError = String(format: text.traditionalFallback, arguments: text.arguments)
            chatErrorText = text
            return
        }
        do { try repository.recordConsentForMain() }
        catch { chatError = Self.settingsMessage(error); return }
        reloadProviders()
        attemptSend(mcp: mcp)
    }

    func dismissSendBlocker() { shownSendBlocker = nil }

    private var quoteSourceIsCurrent: Bool {
        guard pendingQuote != nil else { return quoteSource == nil }
        guard let source = quoteSource, let archive, archive.available,
              archive.state.conversations.first(where: { $0.id == source.id }) == source else { return false }
        return matchesArchivedTranscript(source)
    }

    /// A conversation belongs to a provider and model, not to a key, so a new
    /// key for the same provider keeps it going. The archive's
    /// credentialAccount field holds the provider id; the provider imported
    /// from the v1 setting has that setting's account as its id.
    var archiveDestination: ConversationDestination? {
        guard let savedSettings, let target = savedSettings.accessIdentity?.target else { return nil }
        return try? ConversationDestination(baseURL: savedSettings.baseURL.absoluteString,
            model: target.model, credentialAccount: target.providerID)
    }

    func canOpenConversation(_ record: ArchivedConversation) -> Bool {
        archive?.available == true && hasStoredKey && archiveDestination == record.destination
    }

    func isCurrentConversation(id: UUID) -> Bool { conversationID == id.uuidString }

    /// Reject stale menus, unfinished previews and completed replies that have
    /// not yet been saved. Compare the entire visible transcript, not just IDs.
    private func matchesArchivedTranscript(_ record: ArchivedConversation) -> Bool {
        let expected = record.turns.flatMap { turn in
            [ChatEntry(id: turn.userID, role: "user", content: turn.userText, pdf: turn.pdf,
                       attachments: turn.attachments.map(ChatAttachmentItem.init(archived:))),
             ChatEntry(id: turn.assistantID, role: "assistant", content: turn.assistantText)]
        }
        return isCurrentConversation(id: record.id) && entries.count == expected.count
            && zip(entries, expected).allSatisfy { actual, saved in
                actual.id == saved.id && actual.role == saved.role && actual.content == saved.content && actual.pdf == saved.pdf
                    && actual.attachments == saved.attachments
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
        switch entry.role {
        case "user": source = .user
        case "assistant": source = .assistant
        default: return false
        }
        let text = plainText(of: entry)
        guard !text.isEmpty else { return false }
        pendingQuote = .init(source: source, text: text)
        quoteSource = record
        return true
    }

    func clearQuote() { guard !isSubmitting else { return }; pendingQuote = nil; quoteSource = nil }

    /// What copy, quote and select text use, like Android's MessageTarget.text:
    /// a reply's visible text without Markdown, or your own words without the
    /// quote and attachment lines.
    func plainText(of entry: ChatEntry) -> String {
        let text = entry.role == "assistant" ? assistantQuoteText(entry.content)
            : ConversationQuote.parse(ChatAttachmentLines.displayText(entry.content, items: entry.attachments)).words
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The saved conversation on screen, while nothing runs and the screen
    /// still matches it.
    private var savedConversationOnScreen: ArchivedConversation? {
        guard !isSubmitting, replyPreview == nil, pendingArchiveSave == nil, let archive, archive.available,
              let id = UUID(uuidString: conversationID),
              let record = archive.state.conversations.first(where: { $0.id == id }),
              matchesArchivedTranscript(record) else { return nil }
        return record
    }

    var messageActionTargets: ChatMessageActionTargets {
        guard let record = savedConversationOnScreen else { return .none }
        let saved = Set(record.turns.flatMap { [$0.userID, $0.assistantID] })
        // A branch opens only under the model setup its conversation was saved with.
        guard canOpenConversation(record) else { return ChatMessageActionTargets(saved: saved, replies: [], questions: []) }
        return ChatMessageActionTargets(
            saved: saved, replies: Set(record.turns.map(\.assistantID)),
            questions: Set(record.turns.filter { !$0.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.userID)))
    }

    /// 從這裡分支: the turns through this finished reply become a new
    /// conversation, titled by `title` from the source, and it opens with an
    /// empty input bar. Like Android (ChatScreen onBranch), whatever waited
    /// there (draft, quote, attachments) is cleared without asking; a failed
    /// branch leaves it as it was.
    func branch(fromReply replyID: UUID, title: (ArchivedConversation) -> String) -> ChatBranchOutcome {
        guard let record = savedConversationOnScreen, record.turns.contains(where: { $0.assistantID == replyID }) else {
            return .failed
        }
        do { try commitBranch(prepareBranch(source: record, assistantID: replyID, title: title(record))) }
        catch { return .failed }
        chatNotice = nil
        return .created
    }

    /// 從這裡重新問: a new conversation with the turns before this message of
    /// yours and its words in the input bar in place of the draft, nothing
    /// sent. Like Android (ChatScreen onBranchRetry), the waiting quote and
    /// attachments are cleared. The first message has nothing before it, so
    /// that is a new, unsaved conversation.
    func askAgain(from messageID: UUID, title: (ArchivedConversation) -> String) -> ChatBranchOutcome {
        guard let record = savedConversationOnScreen, canOpenConversation(record),
              let index = record.turns.firstIndex(where: { $0.userID == messageID }),
              let entry = entries.first(where: { $0.id == messageID }) else { return .failed }
        let words = ConversationQuote.parse(ChatAttachmentLines.displayText(entry.content, items: entry.attachments)).words
        let reattach = !entry.attachments.isEmpty || entry.pdf != nil
        if index == 0 {
            // A new conversation keeps the draft; the quote must go first.
            clearComposerQuote()
            newConversation()
            guard entries.isEmpty else { return .failed }
        } else {
            do {
                try commitBranch(prepareBranch(source: record, assistantID: record.turns[index - 1].assistantID,
                                               title: title(record)))
            } catch { return .failed }
            chatNotice = nil
        }
        draft = words
        return reattach ? .needsReattach : index == 0 ? .startedOver : .created
    }

    /// A reply still arriving or not yet saved blocks branching. The input bar
    /// does not: like Android, a branch opens with it cleared.
    private var branchHasUnfinishedOrUnsavedWork: Bool {
        replyPreview != nil || pendingArchiveSave != nil || archiveNotice != nil
    }

    /// The quote waiting above the input bar, dropped for a branch.
    private func clearComposerQuote() { pendingQuote = nil; quoteSource = nil }

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
        // Saved: like Android, the branch opens with an empty input bar. The
        // quote goes here; opening clears the draft and waiting attachments.
        clearComposerQuote()
        // No suspension occurs between persistence and opening. If opening ever
        // becomes unavailable, the saved branch remains recoverable in archive.
        guard openConversation(id: plan.branch.id) else { throw ConversationArchiveError.unavailable }
        return plan.branch.id
    }

    @discardableResult func openConversation(id: UUID) -> Bool {
        guard pendingQuote == nil, let record = archive?.state.conversations.first(where: { $0.id == id }),
              canOpenConversation(record) else { return false }
        // Publish restored entries only after submitting and approvals have ended.
        // Restored text cannot complete a notification ticket or resume a task.
        cancel()
        newConversation()
        usesMCP = false
        conversationID = record.id.uuidString
        conversationDestination = record.destination
        draft = ""
        entries = record.turns.flatMap { [ChatEntry(id: $0.userID, role: "user", content: $0.userText, pdf: $0.pdf,
                                                   attachments: $0.attachments.map(ChatAttachmentItem.init(archived:))),
                                         ChatEntry(id: $0.assistantID, role: "assistant", content: $0.assistantText)] }
        chatNotice = "已開啟保存的對話；尚未傳送任何訊息。"
        return true
    }

    @discardableResult func deleteConversation(id: UUID) -> Bool {
        guard !isCurrentConversation(id: id) || pendingQuote == nil else { return false }
        if conversationID == id.uuidString { cancel() }
        guard archive?.delete(id: id) == true else { return false }
        attachmentStore.deleteConversation(id.uuidString,
            keeping: ChatAttachmentStore.referencedFolders(in: archive?.state.conversations ?? []))
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

    /// The main model for work outside the chat (browser research, documents,
    /// transcripts, skills). Refused until the user agreed to send content to
    /// its provider. Each call takes a fresh session header value: one run.
    func modelAccess() throws -> ModelAccess {
        guard let savedSettings, hasStoredKey, let identity = savedSettings.accessIdentity else {
            throw HTTPChatModelError.invalidConfiguration
        }
        guard !mainNeedsConsent else { throw ModelSettingsError.consentRequired }
        return ModelAccess(client: client, configuration: savedSettings.configuration(conversation: nil),
                           key: try repository.key(for: savedSettings), identity: identity)
    }

    /// The model client a connection test in Settings › 模型 uses: the UI
    /// test fixture in UI test mode, otherwise HTTPS.
    var connectionTestClient: any ChatModelClient { client }

    /// A saved provider's key for a test call; empty for one saved without a key.
    func providerKey(id: UUID) throws -> String { try repository.storedKey(forProvider: id) }

    // Keep the state typed so language changes re-render the current status.
    var chatStatusMessage: AppText {
        if pendingProfileReview != nil { return .chatStatusProfileReview }
        if pendingMemoryReview != nil { return .chatStatusMemoryReview }
        if isSubmitting && isMCPRun { return .chatStatusMCPWorking }
        if isSubmitting { return .chatStatusWaiting }
        return savedSettings != nil && hasStoredKey ? .chatStatusConfigured : .chatStatusUnconfigured
    }

    var chatStatus: String { chatStatusMessage.traditionalFallback }

    /// The single form's save from the drafts (phase 1a), kept for the App
    /// harnesses; Settings › 模型 calls addProvider and chooseMainModel.
    func saveSettings() {
        guard !isSubmitting else { return }
        guard pendingQuote == nil else { settingsError = "請先傳送或移除引用，再變更模型設定。"; return }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        do {
            let result = try repository.save(baseURL: baseURLDraft, model: modelDraft, newKey: keyDraft)
            // Only another provider or model starts over; a new key for the
            // same provider keeps the conversation and its draft going.
            let changed = savedSettings?.baseURL != result.record.baseURL
                || savedSettings?.accessIdentity?.target != result.record.accessIdentity?.target
            savedSettings = result.record
            hasStoredKey = true
            baseURLDraft = result.record.baseURL.absoluteString
            modelDraft = result.record.model
            keyDraft = ""
            if changed {
                entries = []
                replyPreview = nil
                pendingQuote = nil
                quoteSource = nil
                conversationDestination = nil; archiveNotice = nil; pendingArchiveSave = nil
                profileReceipt = nil
                profileReceiptRequestID = nil
                memoryReceipt = nil
                memoryReceiptRequestID = nil
                discardPendingAttachments()
                conversationID = UUID().uuidString
                learning.resetConversationPresentation()
            }
            chatError = nil
            chatNotice = nil
            shownSendBlocker = nil
            settingsNotice = result.cleanupFailed
                ? "新設定已儲存，尚未驗證連線。舊金鑰清理失敗，可用移除功能清除此 App 的模型金鑰。"
                : "設定已儲存，尚未驗證連線。"
        } catch {
            settingsError = Self.settingsMessage(error)
        }
        reloadProviders()
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
            discardPendingAttachments()
            conversationID = UUID().uuidString
            learning.resetConversationPresentation()
            chatError = nil
            chatNotice = nil
            settingsNotice = "已移除此 App 的模型設定與金鑰；訊息草稿保留。"
        } catch {
            settingsError = Self.settingsMessage(error)
        }
        reloadProviders()
    }

    // MARK: Settings › 模型 (Android ModelSetupViewModel)

    /// Saves the add-provider form: "測試並儲存" after its test passed
    /// (`tested`) or "不測試，直接儲存". `consented`: the user agreed on the
    /// consent screen just now; a save that makes the first main model needs
    /// it. Returns whether the provider was saved.
    @discardableResult
    func addProvider(name: String, baseURL: String, sessionHeader: String?, keyRequired: Bool, key: String,
                     model: String?, tested: Bool, consented: Bool) -> Bool {
        guard beginProviderChange() else { return false }
        do {
            let saved = try repository.addProvider(name: name, baseURL: baseURL, sessionHeader: sessionHeader,
                                                   keyRequired: keyRequired, key: key, model: model, tested: tested,
                                                   consentedAt: consented ? Date() : nil)
            // Also when the main model's own provider was saved again with a new key.
            if saved.becameMain || saved.main?.providerID == saved.providerID { adoptMain(saved.main) }
            reloadProviders()
            providerNotice = tested ? .modelSavedTested(name: saved.providerName)
                                    : .modelSavedUntested(name: saved.providerName)
            if saved.cleanupFailed { settingsError = Self.cleanupFailure }
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            return false
        }
    }

    /// Makes a model the main model: from the main-model picker or a model's
    /// "用作" sheet. Another provider than the one agreed to needs `consented`.
    @discardableResult
    func chooseMainModel(providerID: UUID, model: String, typed: Bool, verified: Bool, consented: Bool) -> Bool {
        guard beginProviderChange() else { return false }
        do {
            let record = try repository.chooseMain(ModelRef(providerID: providerID, model: model), typed: typed,
                                                   verified: verified, consentedAt: consented ? Date() : nil)
            adoptMain(record)
            reloadProviders()
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            return false
        }
    }

    /// A model of this provider answered "重新測試".
    func markModelVerified(providerID: UUID, model: String) {
        do { try repository.markVerified(providerID: providerID, model: model); settingsError = nil }
        catch { settingsError = Self.settingsMessage(error) }
        reloadProviders()
    }

    /// Android updateProviderKey. A new key for the main model's provider
    /// keeps the conversation going: it belongs to the provider, not the key.
    @discardableResult
    func changeProviderKey(providerID: UUID, key: String) -> Bool {
        guard beginProviderChange() else { return false }
        do {
            let result = try repository.changeKey(providerID: providerID, newKey: key)
            if result.main?.providerID == providerID { adoptMain(result.main) }
            reloadProviders()
            providerNotice = providerDocument.provider(id: providerID).map { .modelsKeyChanged(name: $0.name) }
            if result.cleanupFailed { settingsError = Self.cleanupFailure }
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            return false
        }
    }

    /// Android removeProvider: the provider and only its key. A main model on
    /// it is no longer chosen, as on Android.
    @discardableResult
    func deleteProvider(id: UUID) -> Bool {
        let name = providerDocument.provider(id: id)?.name
        guard beginProviderChange() else { return false }
        do {
            let cleanupFailed = try repository.removeProvider(id: id)
            adoptMain(try repository.load())
            reloadProviders()
            providerNotice = name.map { .modelsDeleted(name: $0) }
            if cleanupFailed { settingsError = Self.cleanupFailure }
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            return false
        }
    }

    /// The user's "能看圖" answer for one model. Like the old switch, it only
    /// changes what later prompts send.
    func setModelVision(providerID: UUID, model: String, sees: Bool?) {
        guard !isSubmitting else { return }
        do {
            let main = try repository.setVision(sees, providerID: providerID, model: model)
            if let main, main.providerID == savedSettings?.providerID, main.model == savedSettings?.model {
                savedSettings = main
            }
            settingsError = nil
        } catch {
            settingsError = Self.settingsMessage(error)
        }
        reloadProviders()
    }

    /// The consent asked on the model page for a main model whose provider was
    /// never agreed to: recorded on agreement, nothing changes otherwise.
    func agreeToMainProvider() {
        do { try repository.recordConsentForMain(); settingsError = nil }
        catch { settingsError = Self.settingsMessage(error) }
        reloadProviders()
    }

    func clearProviderNotice() { providerNotice = nil; settingsError = nil; settingsNotice = nil }

    /// Like saving the old form: no change during a reply or with a quote
    /// waiting, and running work and learning stop first.
    private func beginProviderChange() -> Bool {
        guard !isSubmitting else { return false }
        guard pendingQuote == nil else { settingsError = "請先傳送或移除引用，再變更模型設定。"; return false }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        providerNotice = nil
        return true
    }

    /// The main model after a change in Settings › 模型. Only another
    /// provider or model starts over; a new key for the same provider keeps
    /// the conversation, its draft and its attachments.
    private func adoptMain(_ record: SavedModelSettings?) {
        let changed = savedSettings?.baseURL != record?.baseURL
            || savedSettings?.accessIdentity?.target != record?.accessIdentity?.target
        savedSettings = record
        hasStoredKey = record.map { (try? repository.key(for: $0)) != nil } ?? false
        baseURLDraft = record?.baseURL.absoluteString ?? ""
        modelDraft = record?.model ?? ""
        keyDraft = ""
        if changed { startOverForNewModel() }
        chatError = nil
        chatNotice = nil
        shownSendBlocker = nil
    }

    private func startOverForNewModel() {
        entries = []
        replyPreview = nil
        pendingQuote = nil
        quoteSource = nil
        conversationDestination = nil; archiveNotice = nil; pendingArchiveSave = nil
        profileReceipt = nil
        profileReceiptRequestID = nil
        memoryReceipt = nil
        memoryReceiptRequestID = nil
        discardPendingAttachments()
        conversationID = UUID().uuidString
        learning.resetConversationPresentation()
    }

    /// Mapped to AppText.modelsCleanupFailed for display.
    nonisolated static let cleanupFailure = "設定已儲存，但舊的 API Key 沒能刪掉；下次開啟 App 會再清一次。"

    func send(mcp: MCPSession? = nil) {
        if pendingQuote != nil { archive?.reload() }
        guard quoteSourceIsCurrent else { chatError = "引用來源已變更；草稿與引用保留，請重新選取。"; return }
        guard canSend, let savedSettings else { return }
        if let archive, !entries.isEmpty,
           !archive.state.conversations.contains(where: { $0.id.uuidString == conversationID }) {
            chatError = "原對話已變更或尚未保存；草稿保留，請先確認保存狀態。"
            return
        }
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
        let attachmentsAtStart = pendingAttachments
        // The archived prompt names each attachment, so later turns know what was shared.
        let prompt = ChatAttachmentLines.compose(prompt: ConversationQuote.compose(quoteAtStart, words: draftAtStart),
                                                 items: attachmentsAtStart)
        // Neither quote markers nor quoted text authorize tools or memory.
        // Evidence is exclusively the words actually entered for this request.
        let utterance = draftAtStart
        let archiveID = UUID(uuidString: conversationID)!
        let destination = archiveDestination
        let archivePrior = archive?.state.conversations.first { $0.id == archiveID }
        let learningWasAvailable = learning.available
        let context = learning.contextMessages(for: utterance)
        if learningWasAvailable && !learning.available {
            chatError = (learning.error ?? "無法讀取學習資料，請重新讀取後再試。") + "草稿已保留。"
            return
        }
        let window: ChatContextWindow
        do {
            window = try ChatContextWindow(
                history: entries.map { ModelMessage(role: $0.role, content: $0.content) },
                context: context, prompt: prompt)
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
        // The provider's session header (OpenCode Go) carries this conversation's value.
        let configuration = savedSettings.configuration(conversation: conversationID)
        let contextFence: ChatContextFence?
        let modelClient: any ChatModelClient
        if learning.available && (!context.isEmpty || useLearningTools) {
            let fence = ChatContextFence(store: learning, generation: learningGeneration)
            do { modelClient = try fencedChatClient(client, fence: fence); contextFence = fence }
            catch {
                chatError = "目前模型連線無法確認請求生命週期；參考資料尚未送出，草稿保留。"
                return
            }
        } else { modelClient = client; contextFence = nil }
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
        let client = modelClient
        let extractionClient = self.client
        let attachmentStore = self.attachmentStore
        let attachmentBudget = ChatAttachmentPreparation.textBudget(promptBytes: prompt.utf8.count,
                                                                     contextBytes: context.reduce(0) { $0 + $1.content.utf8.count })
        request = Task { [weak self] in
            do {
                var outgoing = messages
                if !attachmentsAtStart.isEmpty, let last = outgoing.popLast() {
                    // Read the app's own copies off the main actor. Whatever the model
                    // cannot use is named in a note instead of being dropped silently.
                    let prepared = await Task.detached(priority: .userInitiated) {
                        ChatAttachmentPreparation.prepare(attachmentsAtStart, store: attachmentStore,
                                                          vision: configuration.vision, textBudgetBytes: attachmentBudget)
                    }.value
                    try Task.checkCancellation()
                    if prepared.unseenImages > 0 { self?.attachmentNotice = .imagesNotSeen(prepared.unseenImages) }
                    outgoing.append(ModelMessage(userText: ChatAttachmentPreparation.promptText(last.content, notes: prepared.notes),
                                                 attachments: prepared.attachments))
                }
                let reply: String
                if let (connection, tools, resources) = mcpConnection {
                    reply = try await self?.completeWithMCP(messages: outgoing, utterance: utterance,
                        profileState: profileState, memoryState: memoryState, generation: learningGeneration,
                        allowsLearning: useLearningTools, configuration: configuration,
                        key: key, client: client, connection: connection, tools: tools, resources: resources, requestID: id,
                        contextFence: contextFence) ?? ""
                } else if useLearningTools {
                    reply = try await self?.completeWithProfile(messages: outgoing, utterance: utterance,
                        state: profileState, memoryState: memoryState, generation: learningGeneration, configuration: configuration,
                        key: key, client: client, requestID: id, contextFence: contextFence) ?? ""
                } else {
                    reply = try await self?.completePlain(messages: outgoing, configuration: configuration,
                        key: key, client: client, requestID: id, contextFence: contextFence) ?? ""
                }
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                // Keep peer edits fenced until the final reply is published.
                let publicationLease = try contextFence?.acquire()
                defer { publicationLease?.release() }
                if mcpConnection != nil { self.mcpPhase = "finished"; self.updateMCPDiagnostics() }
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.finish(id: id, error: "模型回傳空白內容，草稿已保留，請重試。")
                    return
                }
                let userEntry = ChatEntry(role: "user", content: prompt, attachments: attachmentsAtStart.map(\.sent))
                let assistantEntry = ChatEntry(role: "assistant", content: reply)
                if let archive = self.archive {
                    self.pendingArchiveSave = nil
                    do {
                        guard let destination else { throw ConversationArchiveError.invalidData }
                        let all = self.entries + [userEntry, assistantEntry]
                        let turns = try stride(from: 0, to: all.count, by: 2).map { index in
                            try ArchivedConversationTurn(userID: all[index].id, assistantID: all[index + 1].id,
                                userText: all[index].content, assistantText: all[index + 1].content, pdf: all[index].pdf,
                                attachments: all[index].attachments.map { try $0.archived() })
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
                // Sent attachments now belong to the transcript; their files stay.
                if self.pendingAttachments == attachmentsAtStart { self.pendingAttachments = [] }
                publicationLease?.release()
                self.finish(id: id)
                // Deliver first. Extraction receives the user's own utterance and
                // relevant saved memories, never the model reply or MCP/web content.
                self.learning.rememberAfterReply(utterance: utterance, conversationID: self.conversationID,
                    expectedGeneration: learningGeneration, client: extractionClient, configuration: configuration, apiKey: key,
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
                let fenceFailure: Error?
                do { try contextFence?.check(); fenceFailure = nil }
                catch { fenceFailure = error }
                let message = fenceFailure.flatMap(Self.profileFailureMessage)
                    ?? (error as? MCPChatStop)?.message
                    ?? (error as? ProfileChatStop)?.message
                    ?? Self.profileFailureMessage(error)
                    ?? Self.modelFailureMessage(error as? MCPConversationError)
                    ?? ((error as? MCPConversationError) == .invalidCommand
                        ? "模型仍未提供可用的單一步驟指令，已停止；草稿與先前工具結果保留。" : nil)
                    ?? (mcpConnection == nil ? "傳送失敗，草稿已保留。請檢查模型設定或網路後重試。"
                        : "MCP 對話未完成，草稿與已收到的工具結果保留；請先確認已送出操作，不會自動重試。")
                // A plain request names its model failure like Android (ModelErrorCopy).
                let modelFailure = fenceFailure == nil && mcpConnection == nil ? ChatModelFailure(error) : nil
                if self.memoryReceiptRequestID == id {
                    self.finish(id: id, error: "記憶修改已儲存，但後續模型回覆未完成；請先查看保存結果或撤銷，避免重複修改。草稿保留。")
                } else if let modelFailure, self.profileReceiptRequestID != id {
                    self.finish(id: id, error: modelFailure.traditionalText, text: modelFailure.text)
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

    /// Copies picked photos and files into this conversation's folder. The tray
    /// keeps at most nine; the rest and anything too large are named in a notice.
    func addAttachments(_ picked: [ChatPickedFile]) async {
        // One batch at a time, so quick taps on recent photos all land in order.
        let previous = attachmentImport
        let task = Task { @MainActor [weak self] in
            await previous?.value
            await self?.importAttachments(picked)
        }
        attachmentImport = task
        await task.value
    }

    /// A picker is still copying photos (for example originals from iCloud):
    /// "+" and send wait, and the input bar says so.
    func attachmentsLoadingStarted() {
        guard !isSubmitting else { return }
        isAddingAttachments = true
    }

    private func importAttachments(_ picked: [ChatPickedFile]) async {
        guard !picked.isEmpty, !isSubmitting else {
            ChatAttachmentImport.discardTemporary(picked)
            isAddingAttachments = false
            return
        }
        isAddingAttachments = true
        defer { isAddingAttachments = false }
        let store = attachmentStore, conversation = conversationID, existing = pendingAttachments
        let outcome = await Task.detached(priority: .userInitiated) {
            store.importFiles(picked, conversationID: conversation, existing: existing)
        }.value
        // A new conversation started meanwhile: these belong to nobody.
        guard conversation == conversationID else { store.discard(outcome.added); return }
        // Removals during the copy are kept; the limit is checked again against the tray now.
        let room = max(0, ChatAttachmentLimits.maximumCount - pendingAttachments.count)
        let kept = Array(outcome.added.prefix(room))
        store.discard(Array(outcome.added.dropFirst(room)))
        pendingAttachments += kept
        let overflow = outcome.overflow + (outcome.added.count - kept.count)
        if !outcome.refused.isEmpty { attachmentNotice = .refused(outcome.refused) }
        else if overflow > 0 { attachmentNotice = .overLimit(overflow) }
    }

    func removeAttachment(id: UUID) {
        guard !isSubmitting, let item = pendingAttachments.first(where: { $0.id == id }) else { return }
        pendingAttachments.removeAll { $0.id == id }
        attachmentStore.discard([item])
    }

    func dismissAttachmentNotice() { attachmentNotice = nil }

    /// Android clears the tray for a new or different chat; unsent copies are deleted.
    private func discardPendingAttachments() {
        let unsent = pendingAttachments
        pendingAttachments = []
        attachmentNotice = nil
        attachmentStore.discard(unsent)
    }

    /// The "能看圖" answer for the saved model. It changes only what later prompts send.
    var seesImages: Bool? { savedSettings?.seesImages }

    func setSeesImages(_ value: Bool?) {
        guard !isSubmitting, savedSettings != nil else { return }
        do { savedSettings = try repository.setSeesImages(value); settingsError = nil }
        catch { settingsError = Self.settingsMessage(error) }
    }

    private func completePlain(messages: [ModelMessage], configuration: ModelConfiguration,
                               key: String, client: any ChatModelClient, requestID id: UUID,
                               contextFence: ChatContextFence?) async throws -> String {
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        guard let streaming = client as? any StreamingChatModelClient else {
            return try await client.complete(messages: messages, configuration: configuration, apiKey: key)
        }
        var text = "", bytes = 0, resent = false
        while true {
            do {
                for try await delta in streaming.stream(messages: messages, configuration: configuration, apiKey: key) {
                    try Task.checkCancellation()
                    guard requestID == id else { throw CancellationError() }
                    guard delta.utf8.count <= ChatReplyPreview.maximumUTF8Bytes - bytes else {
                        throw HTTPChatModelError.responseTooLarge
                    }
                    guard !delta.isEmpty else { continue }
                    let publicationLease = try contextFence?.acquire()
                    defer { publicationLease?.release() }
                    bytes += delta.utf8.count; text += delta
                    replyPreview = ChatReplyPreview(id: id, text: text, phase: .receiving)
                }
                break
            } catch HTTPStreamFallbackError.usageOptionUnsupported where !resent && bytes == 0 {
                // Only the usage option was refused, before any text. The client
                // now leaves it out for this endpoint and model: resend once.
                resent = true
                try Task.checkCancellation()
                guard requestID == id else { throw CancellationError() }
            }
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
        guard let id = requestID else { return }
        if isMCPRun { updateMCPDiagnostics(failure: "cancelled") }
        stopPreview(id: id, phase: .cancelled)
        request?.cancel()
        finish(id: id)
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
                                     client: any ChatModelClient, requestID: UUID,
                                     contextFence: ChatContextFence?) async throws -> String {
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
                try contextFence?.check()
                guard self.learning.available, self.learning.memory.preferences.useMemory,
                      self.learning.generation == generation,
                      self.learning.profile.revision == expectedProfileRevision,
                      self.learning.memory.revision == expectedMemoryRevision else {
                    self.replyPreview = nil
                    throw UserProfileToolError.staleRevision
                }
            }) { [weak self] answer in
                guard let self, self.requestID == requestID, !Task.isCancelled else { return }
                let publicationLease: EncryptedLearningFile.ExclusiveLease?
                do { publicationLease = try contextFence?.acquire() }
                catch { self.replyPreview = nil; return }
                defer { publicationLease?.release() }
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
                try contextFence?.check()
                let before = learning.profile
                let receipt = try learning.commitProfileTool(proposal, expectedGeneration: generation)
                profileReceipt = receipt // Retained even if the next model call fails.
                profileReceiptRequestID = requestID
                if proposal.op == .add { try contextFence?.acceptProfileAddition(before: before, receiptID: receipt.id) }
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
                try contextFence?.check()
                let before = learning.memory
                let receipt = try learning.commitMemoryTool(review, expectedGeneration: generation,
                    conversationID: conversationID)
                memoryReceipt = receipt
                memoryReceiptRequestID = requestID
                if review.op == .add { try contextFence?.acceptMemoryAddition(before: before, receiptID: receipt.id) }
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
        if (error as? LearningFileError) == .busy {
            return "學習資料正在其他位置儲存；本次修改未儲存，草稿保留。請稍後重新確認。"
        }
        if (error as? LearningFileError) == .conflict {
            return "學習資料已變更；本次對話已停止，草稿保留。請重新讀取資料並再次確認。"
        }
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
                                 connection: any MCPDiscovering, tools: [MCPTool], resources: [MCPResource], requestID: UUID,
                                 contextFence: ChatContextFence?) async throws -> String {
        let turn = MCPLearningTurn(profile: profileState, memory: memoryState,
                                   utterance: utterance, generation: generation)
        let local: MCPLocalHandler?
        if allowsLearning {
            local = { [weak self] proposal, lease in
                guard let self else { throw CancellationError() }
                return try await self.performMCPLocal(proposal, lease: lease, turn: turn, requestID: requestID, contextFence: contextFence)
            }
        } else { local = nil }
        // Like the Play build, selected tools and offered resources run with no
        // per-call approval: the tool selection in MCP settings is the limit.
        // The fenced executor still rechecks the learning context before each call.
        let executor: any MCPConversationExecuting
        if let contextFence { executor = ContextFencedMCPExecutor(executor: connection, fence: contextFence) }
        else { executor = connection }
        let result = try await MCPConversationRunner(client: client).run(
            messages: messages, configuration: configuration, apiKey: key,
            tools: tools, resources: resources, executor: executor,
            onEvent: { [weak self] event in
                await self?.receiveMCP(event, requestID: requestID)
            }, handleLocal: local)
        guard result.stopReason == .finished, let answer = result.answer else { throw MCPChatStop(reason: result.stopReason) }
        return answer
    }

    /// Local learning and the remote MCP connection are separate capabilities.
    /// Every proposal is validated against this turn's captured user utterance;
    /// remote catalogs/results cannot supply that authority or replace its IDs.
    private func performMCPLocal(_ proposal: MCPLocalProposal, lease: MCPLocalLease,
                                 turn: MCPLearningTurn, requestID: UUID,
                                 contextFence: ChatContextFence?) async throws -> MCPLocalOutcome {
        try lease.check()
        try contextFence?.check()
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
            try contextFence?.check()
            let before = learning.profile
            let receipt = try learning.commitProfileTool(review, expectedGeneration: turn.generation)
            profileReceipt = receipt
            profileReceiptRequestID = requestID
            if review.op == .add { try contextFence?.acceptProfileAddition(before: before, receiptID: receipt.id) }
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
            try contextFence?.check()
            let before = learning.memory
            let receipt = try learning.commitMemoryTool(review, expectedGeneration: turn.generation,
                                                        conversationID: conversationID)
            memoryReceipt = receipt
            memoryReceiptRequestID = requestID
            if review.op == .add { try contextFence?.acceptMemoryAddition(before: before, receiptID: receipt.id) }
            return .committedReceipt(json: try receipt.resultJSON())
        }
    }

    private func receiveMCP(_ event: MCPConversationEvent, requestID: UUID) {
        guard self.requestID == requestID else { return }
        switch event {
        case .requestingModel(let count): mcpPhase = "requestingModel"; mcpModelCalls = count
        case .correctingCommand: mcpPhase = "correctingCommand"; mcpFormatCorrections += 1
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

    func newConversation() {
        guard !isSubmitting, pendingQuote == nil else { return }
        discardPendingAttachments()
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
        shownSendBlocker = nil
    }

    private func finish(id: UUID, error: String? = nil, text: AppText? = nil) {
        guard requestID == id else { return }
        if error != nil { stopPreview(id: id, phase: .failed) }
        if let pending = pendingProfileReview { resolveProfileReview(id: pending.id, approved: false) }
        if let pending = pendingMemoryReview { resolveMemoryReview(id: pending.id, approved: false) }
        requestID = nil
        isSubmitting = false
        isMCPRun = false
        request = nil
        deadline?.cancel()
        deadline = nil
        chatError = error
        chatErrorText = text
    }

    private static func liveRepository() -> ModelSettingsRepository {
        ModelSettingsRepository(defaults: .standard, credentials: KeychainModelCredentials(service: "io.woowtech.assistant.model-credentials.v1"),
                                providers: ModelProvidersFile.live())
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
