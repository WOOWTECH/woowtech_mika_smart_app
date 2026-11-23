import AssistantBrowser
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
        /// Choosing a vision or light model of a provider not agreed to yet.
        case role
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
    /// A reply that did not come: 沒有完成 with its reason, or 已停止。 Like the
    /// Play build these stay in the conversation; nil is an answer.
    let outcome: ArchivedConversationTurn.Outcome?
    init(id: UUID = UUID(), role: String, content: String, pdf: ArchivedPDFAnswer? = nil,
         attachments: [ChatAttachmentItem] = [], outcome: ArchivedConversationTurn.Outcome? = nil) {
        self.id = id; self.role = role; self.content = content
        self.pdf = pdf
        self.attachments = attachments
        self.outcome = outcome
    }
}

/// Display-only text of the reply still arriving. It never becomes a
/// ChatEntry, archive turn, learning utterance or notification completion;
/// a stop or a failure replaces it with the turn's 已停止。 or 沒有完成.
struct ChatReplyPreview: Identifiable, Equatable {
    enum Phase { case receiving }
    static let maximumUTF8Bytes = 4 * 1024 * 1024
    let id: UUID
    let text: String
    var phase: Phase
}

/// Why a typed message cannot start yet. Mirrors the Android store build's
/// chat card (還不能開始任務 / chat.sendBlocked.noModel 「還缺：還沒有能用的模型」) so a tap on
/// send is never silent.
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
    case auth, quota, rateLimited, notFound, network, streamCut, truncated, unreadable
    case server(Int), status(Int)
    /// An account sign-in (ChatGPT, xAI) failed for its own reason; the
    /// associated value is the account's brand name.
    case signedOut(String), chatGPTLimit, chatGPTNotEligible, planNotAllowed(String), refused, context

    init?(_ error: Error) {
        if let account = error as? ModelAccountError {
            switch account {
            case .signInExpired(let kind), .unauthorized(let kind): self = .signedOut(kind.accountName)
            case .planLimitReached: self = .chatGPTLimit
            case .planNotEligible: self = .chatGPTNotEligible
            case .planNotAllowed(let kind): self = .planNotAllowed(kind.accountName)
            case .contentRefused: self = .refused
            case .contextTooLong: self = .context
            }
            return
        }
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
        case .truncatedResponse: self = .truncated
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
        case .truncated: return .chatModelFailedTruncated
        case .unreadable: return .chatModelFailedUnreadable
        case .server(let status): return .chatModelFailedServer(status: status)
        case .status(let status): return .chatModelFailedStatus(status: status)
        case .signedOut(let account): return .chatModelFailedSignedOut(account: account)
        case .chatGPTLimit: return .chatModelFailedChatGPTLimit
        case .chatGPTNotEligible: return .chatModelFailedChatGPTNotEligible
        case .planNotAllowed(let account): return .chatModelFailedPlan(account: account)
        case .refused: return .chatModelFailedRefused
        case .context: return .chatModelFailedContext
        }
    }
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

/// An ordinary chat reply, or the command that starts a web task or the MCP step.
enum ChatPathReply {
    case answer(String)
    /// `exchange` is what an MCP step before it did (MCPConversationHandoffRequest).
    case web(ChatWebCommand, raw: String, exchange: [ModelMessage] = [])
    /// A first MCP command, and the memory search a memory chat made before it.
    case mcp(MCPConversationEntry, memory: MemoryToolRun?)

    /// A plain reply is a web entry only when it is exactly that command.
    static func plain(_ text: String, allowsWeb: Bool) -> ChatPathReply {
        if allowsWeb, let command = try? ChatWebCommand.parseEntry(text) {
            return .web(command, raw: ChatWebCommand.unfenced(text))
        }
        return .answer(text)
    }
}

/// Draft edits should update the composer without invalidating the transcript.
@MainActor
final class ChatDraft: ObservableObject {
    @Published var text = ""
}

@MainActor
final class ChatSession: ObservableObject {
    /// MCP runs keep a host deadline; ordinary chat has none, like the Play build.
    /// Just past the MCP runner's own 30-minute limit, so the runner's stop comes first.
    static let mcpRequestDeadlineSeconds: UInt64 = 1830
    /// The archived marker of a stopped turn, shown as 已停止。 (Play's CANCELLED_OUTCOME).
    nonisolated static let stoppedMarker = "已取消"
    let learning: LearningStore
    let archive: ConversationArchiveStore?
    @Published private(set) var conversationID = UUID().uuidString
    /// The question on its way: already in the transcript, saved with its outcome.
    private struct PendingTurn {
        let requestID: UUID
        let user: ChatEntry
        let archiveID: UUID
        let destination: ConversationDestination?
        var prior: ArchivedConversation?
    }
    private var pendingTurn: PendingTurn?
    /// The request whose turn was already saved as unfinished when the app left the screen.
    private var checkpointedRequestID: UUID?
    /// When the request on its way started; the working row shows the time since.
    @Published private(set) var requestStartedAt: Date?
    @Published private(set) var archiveNotice: String?
    private var pendingArchiveSave: (record: ArchivedConversation, expected: ArchivedConversation?)?
    var canRetryArchiveSave: Bool { pendingArchiveSave != nil && !isSubmitting }
    let draftModel = ChatDraft()
    var draft: String {
        get { draftModel.text }
        set { draftModel.text = newValue }
    }
    @Published private(set) var pendingQuote: ConversationQuote.Quote?
    private var quoteSource: ArchivedConversation?
    @Published var baseURLDraft = ""
    @Published var modelDraft = ""
    @Published var keyDraft = ""
    /// Changes only when transcript data changes, never on a layout pass.
    private(set) var transcriptContentRevision: UInt64 = 0
    @Published private(set) var entries: [ChatEntry] = [] {
        didSet { transcriptContentRevision &+= 1 }
    }
    @Published private(set) var replyPreview: ChatReplyPreview? {
        didSet {
            if replyPreview != oldValue { transcriptContentRevision &+= 1 }
        }
    }
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
    /// Android pickToProbe: the provider just saved without a test while no
    /// main model is chosen; Settings › 模型 offers 選主模型 for it.
    @Published private(set) var pickMainProvider: UUID?
    private var consentMCP: MCPServers?
    @Published private(set) var mcpActivity: String?
    /// The vision model is looking at this turn's pictures for the main model (ChatVisionHandoff).
    @Published private(set) var visionLooking = false
    @Published private(set) var mcpSteps: [MCPConversationStep] = []
    /// Which server and tool each step used, for the results list.
    @Published private(set) var mcpStepOwners: [UUID: MCPStepOwner] = [:]
    /// Enabled servers the last request could not reach (the user's names, ""
    /// for an unnamed one); the request went on with the others.
    @Published private(set) var mcpUnavailableServers: [String] = []
    /// Tools and resources the last request left out to stay within the limits.
    @Published private(set) var mcpOmitted = 0
    /// The skill tool running in this request (Play's chat step labels).
    @Published private(set) var skillStep: ChatSkillStep?
    /// The skills a skill step read, for learning after the reply (ChatLearning.swift).
    var pendingSkillLearning: ChatSkillLearningInput?
    @Published private(set) var mcpDiagnostics: String?
    @Published private(set) var profileReceipt: UserProfileToolReceipt?
    private var profileReceiptRequestID: UUID?
    @Published private(set) var memoryReceipt: MemoryToolReceipt?
    /// The web task this request started, while it runs and three seconds after.
    @Published private(set) var webTask: ChatWebTaskSession?
    /// The browser's website data and search engine; set by the root view.
    /// Without it (MCP conversations, hosted tests) chat offers no web tasks.
    var webTaskEnvironment: (@MainActor () -> ChatWebTaskEnvironment?)?
    /// The interface language for text a web task writes into the conversation.
    var interfaceLanguage: @MainActor () -> AppDisplayLanguage = { .traditionalChinese }
    private var memoryReceiptRequestID: UUID?
    /// The request whose own memory tool forgot an entry; its words are not
    /// organized again afterwards (see LearningStore.rememberAfterReply).
    private var memoryForgotRequestID: UUID?
    /// A successful skill save already handled this request's procedure.
    private var skillSavedRequestID: UUID?
    private var mcpPhase = "idle"
    private var mcpModelCalls = 0
    private var mcpFormatCorrections = 0
    /// The MCP step of this request is running: leaving the app or changing a
    /// server stops it (cancelMCP), as iOS stops MCP work in the background.
    private var isMCPRun = false
    /// This request reached its MCP step; its failures read as MCP failures.
    private var mcpReached = false
    /// The servers this request connected, while it runs.
    private var mcpRequestCatalog: MCPChatCatalog?
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
    /// The request that was still arriving when the app left the screen (keptReply).
    private var requestLeftScreen: UUID?
    /// The request whose memory or profile command the host refused: organizing
    /// its words into memory afterwards would save what was just turned down.
    private var localCommandRefusedRequestID: UUID?
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
            client = Self.providerClient(repository)
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
            client = Self.providerClient(repository)
            isUITestMode = false
        }
        #else
        repository = Self.liveRepository()
        client = Self.providerClient(repository)
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
    /// Every chat may use the enabled MCP servers in `mcp`; nothing is switched on per chat.
    func attemptSend(mcp: MCPServers? = nil) {
        guard canAttemptSend else { return }
        guard savedSettings != nil, hasStoredKey else { shownSendBlocker = .noModel; return }
        shownSendBlocker = nil
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

    /// Like the Play build, a conversation is not tied to the model it was saved
    /// with: it opens and continues with the current main model.
    func canOpenConversation(_ record: ArchivedConversation) -> Bool {
        archive?.available == true
    }

    func isCurrentConversation(id: UUID) -> Bool { conversationID == id.uuidString }

    /// Reject stale menus, unfinished previews and completed replies that have
    /// not yet been saved. Compare the entire visible transcript, not just IDs.
    private func matchesArchivedTranscript(_ record: ArchivedConversation) -> Bool {
        let expected = record.turns.flatMap { turn in
            [ChatEntry(id: turn.userID, role: "user", content: turn.userText, pdf: turn.pdf,
                       attachments: turn.attachments.map(ChatAttachmentItem.init(archived:))),
             ChatEntry(id: turn.assistantID, role: "assistant", content: turn.assistantText, outcome: turn.outcome)]
        }
        return isCurrentConversation(id: record.id) && entries.count == expected.count
            && zip(entries, expected).allSatisfy { actual, saved in
                actual.id == saved.id && actual.role == saved.role && actual.content == saved.content && actual.pdf == saved.pdf
                    && actual.attachments == saved.attachments && actual.outcome == saved.outcome
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
        guard canOpenConversation(record) else { return ChatMessageActionTargets(saved: saved, replies: [], questions: []) }
        // Like the Play build 從這裡分支 is on answers; 沒有完成 and 已停止。 are not
        // replies (a branch or 從這裡重新問 still copies them along).
        return ChatMessageActionTargets(
            saved: saved, replies: Set(record.turns.filter { $0.outcome == nil }.map(\.assistantID)),
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
        let evicted = try archive.commitBranch(plan, isBusy: isSubmitting,
                                               hasUnfinishedOrUnsavedTurn: branchHasUnfinishedOrUnsavedWork)
        deleteAttachments(ofEvicted: evicted)
        // Saved: like Android, the branch opens with an empty input bar. The
        // quote goes here; opening clears the draft and waiting attachments.
        clearComposerQuote()
        // No suspension occurs between persistence and opening. If opening ever
        // becomes unavailable, the saved branch remains recoverable in archive.
        guard openConversation(id: plan.branch.id) else { throw ConversationArchiveError.unavailable }
        return plan.branch.id
    }

    @discardableResult func openConversation(id: UUID) -> Bool {
        guard let found = archive?.state.conversations.first(where: { $0.id == id }),
              canOpenConversation(found) else { return false }
        // Publish restored entries only after submitting and approvals have ended.
        // Restored text cannot complete a notification ticket or resume a task.
        // A stop saves its 已停止。 first, so the row is read again after it.
        cancel()
        guard let record = archive?.state.conversations.first(where: { $0.id == id }) else { return false }
        newConversation()
        conversationID = record.id.uuidString
        draft = ""
        entries = record.turns.flatMap { [ChatEntry(id: $0.userID, role: "user", content: $0.userText, pdf: $0.pdf,
                                                   attachments: $0.attachments.map(ChatAttachmentItem.init(archived:))),
                                         ChatEntry(id: $0.assistantID, role: "assistant", content: $0.assistantText,
                                                   outcome: $0.outcome)] }
        chatNotice = "已開啟保存的對話；尚未傳送任何訊息。"
        return true
    }

    @discardableResult func deleteConversation(id: UUID) -> Bool {
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

    private static let archiveSaveFailure = "回覆已顯示，但本次對話未能保存；關閉程序後可能遺失。"

    /// The main model for work outside the chat (browser research, documents,
    /// transcripts, skills). Refused until the user agreed to send content to
    /// its provider. Each call takes a fresh session header value: one run.
    func modelAccess() throws -> ModelAccess {
        guard let savedSettings, hasStoredKey, let identity = savedSettings.accessIdentity else {
            throw HTTPChatModelError.invalidConfiguration
        }
        // Owner decision 2026-11-13: until the consent is given (a setting from
        // before it), work outside the chat keeps its own "model unavailable"
        // errors. A later consent prompt for these features would hook in here.
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
        if isSubmitting && isMCPRun { return .chatStatusMCPWorking }
        if isSubmitting { return .chatStatusWaiting }
        return savedSettings != nil && hasStoredKey ? .chatStatusConfigured : .chatStatusUnconfigured
    }

    var chatStatus: String { chatStatusMessage.traditionalFallback }

    /// The single form's save from the drafts (phase 1a), kept for the App
    /// harnesses; Settings › 模型 calls addProvider and chooseMainModel. Like
    /// them, and like the Play build, the conversation stays.
    func saveSettings() {
        guard !isSubmitting else { return }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        do {
            let result = try repository.save(baseURL: baseURLDraft, model: modelDraft, newKey: keyDraft)
            savedSettings = result.record
            hasStoredKey = true
            baseURLDraft = result.record.baseURL.absoluteString
            modelDraft = result.record.model
            keyDraft = ""
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

    /// The single form's remove (phase 1a), kept for the App harnesses. Like
    /// deleteProvider, the conversation stays; the next send asks for a model.
    func removeSettings() {
        guard !isSubmitting else { return }
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
            // Android saveWithoutTest: with no main model yet, choose one from this
            // provider; the picker tests it before it becomes the main model.
            pickMainProvider = !tested && providerDocument.roles.main == nil ? saved.providerID : nil
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

    /// Android ModelsViewModel.pick for the vision or light role: a model,
    /// 用主模型 or 不用. A model of a provider not agreed to yet needs `consented`.
    @discardableResult
    func chooseRoleModel(_ role: ModelSideRole, _ choice: ModelRoleChoice, typed: Bool = false, verified: Bool = false,
                         consented: Bool) -> Bool {
        guard beginProviderChange() else { return false }
        do {
            try repository.chooseRole(role, choice, typed: typed, verified: verified, consentedAt: consented ? Date() : nil)
            // The vision role decides whether the main model sees images (Android configFor).
            if role == .vision { adoptMain(try repository.load()) }
            reloadProviders()
            return true
        } catch {
            settingsError = Self.settingsMessage(error)
            reloadProviders()
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

    func clearProviderNotice() { providerNotice = nil; settingsError = nil; settingsNotice = nil; pickMainProvider = nil }

    /// Like saving the old form: no change during a reply, and running work
    /// and learning stop first.
    private func beginProviderChange() -> Bool {
        guard !isSubmitting else { return false }
        learning.onUserChange?()
        learning.cancelLearning()
        settingsError = nil
        settingsNotice = nil
        providerNotice = nil
        pickMainProvider = nil
        return true
    }

    /// The main model after a change in Settings › 模型. Like the Play build the
    /// conversation, its draft and its attachments stay: the next message goes
    /// to the new model (after the consent for another provider).
    private func adoptMain(_ record: SavedModelSettings?) {
        savedSettings = record
        hasStoredKey = record.map { (try? repository.key(for: $0)) != nil } ?? false
        baseURLDraft = record?.baseURL.absoluteString ?? ""
        modelDraft = record?.model ?? ""
        keyDraft = ""
        chatError = nil
        chatNotice = nil
        shownSendBlocker = nil
    }

    /// Mapped to AppText.modelsCleanupFailed for display.
    nonisolated static let cleanupFailure = "設定已儲存，但舊的 API Key 沒能刪掉；下次開啟 App 會再清一次。"

    func send(mcp: MCPServers? = nil) {
        if pendingQuote != nil { archive?.reload() }
        guard quoteSourceIsCurrent else { chatError = "引用來源已變更；草稿與引用保留，請重新選取。"; return }
        guard canSend, let savedSettings else { return }
        if let archive, !entries.isEmpty,
           !archive.state.conversations.contains(where: { $0.id.uuidString == conversationID }) {
            chatError = "原對話已變更或尚未保存；草稿保留，請先確認保存狀態。"
            return
        }
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
        let context = Self.withLocalTime(learning.contextMessages(for: utterance))
        if learningWasAvailable && !learning.available {
            chatError = (learning.error ?? "無法讀取學習資料，請重新讀取後再試。") + "草稿已保留。"
            return
        }
        let window: ChatContextWindow
        do {
            window = try ChatContextWindow(
                history: Self.modelHistory(entries),
                context: context, prompt: prompt)
        } catch {
            chatError = ((error as? ChatContextWindowError)?.errorDescription ?? "無法準備本次對話。")
                + "草稿已保留。"
            return
        }
        let messages = window.messages
        learning.clearSkillNotes()
        let learningGeneration = learning.generation
        let profileState = learning.profile
        let memoryState = learning.memory
        let useLearningTools = learning.available && learning.memory.preferences.useMemory
        // Like Play, ordinary chat always offers the skill tools, whatever the
        // memory switches, and every message may also become a web task. Like
        // Android, the enabled MCP servers' tools are offered in every chat too
        // (MCPServers.chatCatalog()); one request can use MCP, then a web task
        // or a skill tool.
        let skillIndex: String?? = .some(chatSkillCatalog().index())
        let webEnvironment = webTaskEnvironment?()
        // The provider's session header (OpenCode Go) carries this conversation's value.
        let configuration = savedSettings.configuration(conversation: conversationID)
        // Android lightModelFactory: organizing memory and judging skills go to
        // the light model when one of its own is chosen and agreed to; else the main one.
        let light: (configuration: ModelConfiguration, key: String)
        if let lightSettings = try? repository.roleSettings(.light), let lightKey = try? repository.key(for: lightSettings) {
            light = (lightSettings.configuration(conversation: conversationID), lightKey)
        } else {
            light = (configuration, key)
        }
        // Android visionModelFactory, for chat pictures: when the main model cannot
        // see them, the vision role's own model (agreed to) looks at them first.
        // A follow-up about the pictures of an earlier turn ("再看一次", "照片裡…"): without
        // new attachments, the vision model looks at them again with this question.
        let revisited: [ChatAttachmentItem] = {
            guard attachmentsAtStart.isEmpty, configuration.vision != .supported,
                  ChatVisionHandoff.asksAboutPictures(utterance) else { return [] }
            return entries.last(where: { $0.role == "user" && !$0.attachments.isEmpty })?.attachments ?? []
        }()
        let visionRoute: (configuration: ModelConfiguration, key: String, model: String)? = {
            guard configuration.vision != .supported, !(attachmentsAtStart.isEmpty && revisited.isEmpty),
                  let settings = try? repository.roleSettings(.vision), settings.seesImages == true,
                  let visionKey = try? repository.key(for: settings) else { return nil }
            return (settings.configuration(conversation: conversationID), visionKey, settings.model)
        }()
        let id = UUID()
        requestID = id
        // Like the Play build the question shows in the conversation at once and
        // the input bar empties; how the turn ends is saved with it.
        let userEntry = ChatEntry(role: "user", content: prompt, attachments: attachmentsAtStart.map(\.sent))
        entries.append(userEntry)
        draft = ""; pendingQuote = nil; quoteSource = nil
        // Sent attachments now belong to the transcript; their files stay.
        pendingAttachments = []
        pendingTurn = PendingTurn(requestID: id, user: userEntry, archiveID: archiveID,
                                  destination: destination, prior: archivePrior)
        requestStartedAt = Date()
        replyPreview = nil
        isSubmitting = true
        isMCPRun = false
        mcpReached = false
        mcpRequestCatalog = nil
        mcpActivity = nil
        mcpSteps = []
        mcpStepOwners = [:]
        mcpUnavailableServers = []
        mcpOmitted = 0
        mcpSentCount = 0
        mcpModelCalls = 0; mcpFormatCorrections = 0; mcpPhase = "starting"; updateMCPDiagnostics()
        chatError = nil
        chatNotice = window.omittedTurns == 0 ? nil
            : "本次傳送最近 \(window.retainedTurns) 輪對話、本輪完整訊息及參考資料；較早 \(window.omittedTurns) 輪仍在畫面中，但未傳送。"
        let client = client
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
                    var notes = prepared.notes, unseen = prepared.unseenImages
                    var visionFailure: ChatVisionFailure?
                    if unseen > 0, let visionRoute {
                        self?.visionLooking = true
                        defer { self?.visionLooking = false }
                        do {
                            if let described = try await ChatVisionHandoff.describe(
                                attachmentsAtStart, store: attachmentStore, question: utterance, client: client,
                                configuration: visionRoute.configuration, key: visionRoute.key) {
                                notes = ChatVisionHandoff.notes(notes, description: described)
                                unseen = 0
                            }
                        } catch {
                            try Task.checkCancellation()
                            visionFailure = ChatVisionFailure(model: visionRoute.model, error: error)
                        }
                        try Task.checkCancellation()
                    }
                    if unseen > 0 {
                        self?.attachmentNotice = visionFailure.map(ChatAttachmentNotice.visionFailed) ?? .imagesNotSeen(unseen)
                    }
                    outgoing.append(ModelMessage(userText: ChatAttachmentPreparation.promptText(last.content, notes: notes),
                                                 attachments: prepared.attachments))
                } else if !revisited.isEmpty, let visionRoute, let last = outgoing.popLast() {
                    var note: String?
                    do {
                        self?.visionLooking = true
                        defer { self?.visionLooking = false }
                        do {
                            if let described = try await ChatVisionHandoff.describe(
                                revisited, store: attachmentStore, question: utterance, client: client,
                                configuration: visionRoute.configuration, key: visionRoute.key) {
                                note = ChatVisionHandoff.lookedAgainNote(described)
                            }
                        } catch {
                            try Task.checkCancellation()
                            // The earlier description stays the only source; the reply says so.
                        }
                    }
                    try Task.checkCancellation()
                    outgoing.append(ModelMessage(role: last.role,
                                                 content: ChatAttachmentPreparation.promptText(last.content, notes: note.map { [$0] } ?? [])))
                }
                // Like Android, every request connects the enabled servers first,
                // all at once and for at most 15 s together; one that is down or
                // slow is left out of this request and named above the chat.
                let mcpCatalog = await mcp?.chatCatalog()
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.mcpRequestCatalog = mcpCatalog
                self.mcpUnavailableServers = mcpCatalog?.unavailable ?? []
                self.mcpOmitted = mcpCatalog?.catalog.omitted ?? 0
                let mcpOffer = mcpCatalog?.instructions
                var path: ChatPathReply
                if useLearningTools {
                    path = try await self.completeWithProfile(messages: outgoing, utterance: utterance,
                        state: profileState, memoryState: memoryState, generation: learningGeneration, configuration: configuration,
                        key: key, client: client, requestID: id, skillIndex: skillIndex,
                        web: webEnvironment.map(Self.webEntry), mcp: mcpOffer)
                } else {
                    path = try await self.completePlain(messages: outgoing, configuration: configuration,
                        key: key, client: client, requestID: id, generation: learningGeneration,
                        skillIndex: skillIndex, utterance: utterance,
                        webOffer: webEnvironment.map { ChatWebTaskPrompts.entryInstructions(searchTemplate: $0.searchTemplate) },
                        mcpOffer: mcpOffer)
                }
                if case .mcp(let entry, let memory) = path, let mcpCatalog {
                    path = try await self.runMCP(entry: entry, catalog: mcpCatalog, messages: outgoing, utterance: utterance,
                        profileState: profileState, memoryRun: memory ?? MemoryToolRun(state: memoryState, utterances: [utterance]),
                        generation: learningGeneration, allowsLearning: useLearningTools, configuration: configuration,
                        key: key, client: client, requestID: id, web: webEnvironment)
                }
                let reply: String
                var webResult: ChatWebTaskResult?
                switch path {
                case .answer(let text): reply = text
                // Only offered with a catalog, so the MCP step above always took it.
                case .mcp: reply = ""
                case .web(let command, let raw, let exchange):
                    guard let webEnvironment else { return }
                    let result = await self.runWebTask(entry: command, raw: raw, conversation: outgoing + exchange, client: client,
                                                       configuration: configuration, key: key,
                                                       environment: webEnvironment, requestID: id)
                    webResult = result
                    reply = ChatWebTaskTranscript.text(for: result, localizer: AppLocalizer(language: self.interfaceLanguage()))
                }
                try Task.checkCancellation()
                guard self.requestID == id else { return }
                if self.mcpReached { self.mcpPhase = "finished"; self.updateMCPDiagnostics() }
                guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.failTurn(id: id, reason: "模型回傳空白內容，請重試。")
                    return
                }
                self.completeTurn(id: id, assistant: ChatEntry(role: "assistant", content: reply))
                // A round that read web pages is not organized into memory, like
                // Android (RunLearning). finish(id:) already retired its tab.
                if let webResult {
                    // Skills are still learned from it, like Play's RunLearning.
                    self.learnFromWebTask(webResult, goal: utterance, generation: learningGeneration,
                                          client: client, configuration: light.configuration, key: light.key)
                    return
                }
                // Deliver first. Extraction receives the user's own utterance and
                // relevant saved memories, never the model reply or MCP/web content.
                if self.localCommandRefusedRequestID != id && self.skillSavedRequestID != id {
                    self.learning.rememberAfterReply(utterance: utterance, conversationID: self.conversationID,
                        expectedGeneration: learningGeneration, client: client, configuration: light.configuration, apiKey: light.key,
                        preservingToolNotes: self.memoryReceiptRequestID == id ? [self.memoryReceipt?.note].compactMap { $0 } : [],
                        toolForgot: self.memoryForgotRequestID == id)
                }
                self.learnFromSkillStep(requestID: id, goal: utterance, answer: reply,
                    priorTurns: self.entries.dropLast(2).suffix(4).map(\.content),
                    client: client, configuration: light.configuration, key: light.key)
            } catch {
                guard let self, self.requestID == id else { return }
                let mcpRan = self.mcpReached
                if !mcpRan, let kept = self.keptReply(after: error, requestID: id) {
                    self.completeTurn(id: id, assistant: ChatEntry(role: "assistant", content: kept))
                    return
                }
                self.recordFailedSkillStep(requestID: id, error: error, generation: learningGeneration)
                if (error as? MCPConversationError) == .executionFailed { self.mcpRequestCatalog?.connectionsFailed() }
                if mcpRan {
                    let category = (error as? MCPConversationError)?.rawValue
                        ?? (error as? MCPChatStop)?.reason.rawValue
                        ?? (error is MCPChatChanged ? "connectionChanged" : nil)
                        ?? (error is CancellationError ? "cancelled" : "unknown")
                    self.updateMCPDiagnostics(failure: category)
                }
                // Do not surface provider error bodies/URLs: they may contain secrets.
                let message = (error as? MCPChatStop)?.message
                    ?? (error is MCPChatChanged ? MCPChatChanged.message : nil)
                    ?? Self.profileFailureMessage(error)
                    ?? Self.modelFailureMessage(error as? MCPConversationError)
                    ?? ((error as? MCPConversationError) == .invalidCommand
                        ? "模型仍未提供可用的單一步驟指令，已停止；先前的工具結果保留。" : nil)
                    ?? (!mcpRan ? "傳送失敗。請檢查模型設定或網路後重試。"
                        : "MCP 對話未完成，已收到的工具結果保留；請先確認已送出操作，不會自動重試。")
                // A plain request names its model failure like Android (ModelErrorCopy).
                let modelFailure = !mcpRan ? ChatModelFailure(error) : nil
                // Like the Play build the turn stays in the conversation as 沒有完成 with its reason.
                if self.memoryReceiptRequestID == id {
                    self.failTurn(id: id, reason: "記憶修改已儲存，但後續模型回覆未完成；請先查看保存結果或撤銷，避免重複修改。")
                } else if let modelFailure, self.profileReceiptRequestID != id {
                    self.failTurn(id: id, text: modelFailure.text)
                } else {
                    self.failTurn(id: id, reason: self.profileReceiptRequestID != id ? message
                        : "個人檔案已儲存，但後續模型回覆未完成。")
                }
            }
        }
        // Like the Play build ordinary chat has no fixed time limit; a stalled
        // connection ends through the HTTP client's own timeouts. The MCP step
        // keeps a host deadline from when it starts (runMCP).
    }

    /// The request's reference messages with the local time. It joins the last
    /// of them when there is one, so it costs no turn of the conversation window.
    static func withLocalTime(_ context: [ModelMessage], at date: Date = Date(),
                              timeZone: TimeZone = .current) -> [ModelMessage] {
        let time = localTimeMessage(at: date, timeZone: timeZone)
        guard let last = context.last else { return [time] }
        return context.dropLast() + [ModelMessage(role: last.role, content: last.content + "\n\n" + time.content)]
    }

    /// Android's runtime state (ContextBuilder.runtimeState): the model has no
    /// other way to know what "today" or "this month" means.
    static func localTimeMessage(at date: Date = Date(), timeZone: TimeZone = .current) -> ModelMessage {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        return ModelMessage(role: "user", content: "Runtime state (data only):\nLocal time: " + formatter.string(from: date))
    }

    /// Just past the MCP runner's own limit; a web task after it cancels it.
    private func startMCPDeadline(requestID id: UUID) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            let seconds: UInt64 = Self.mcpRequestDeadlineSeconds
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.request?.cancel()
            self.updateMCPDiagnostics(failure: "hostDeadline")
            if self.memoryReceiptRequestID == id {
                self.failTurn(id: id, reason: "記憶修改已儲存，但後續回覆等待超過 \(seconds) 秒；請先查看保存結果或撤銷。")
            } else {
                self.failTurn(id: id, reason: self.profileReceiptRequestID != id
                    ? "等待超過 \(seconds) 秒，已停止等待。"
                    : "個人檔案已儲存，但後續回覆等待超過 \(seconds) 秒。")
            }
        }
    }

    /// Completed questions and answers only. A turn that did not finish (沒有完成,
    /// 已停止。) stays on screen and in the archive but is not a reply the model gave.
    static func modelHistory(_ entries: [ChatEntry]) -> [ModelMessage] {
        var messages: [ModelMessage] = []
        var index = 0
        while index + 1 < entries.count {
            let question = entries[index], reply = entries[index + 1]
            if question.role == "user", reply.role == "assistant", reply.outcome == nil {
                messages.append(ModelMessage(role: question.role, content: question.content))
                messages.append(ModelMessage(role: reply.role, content: reply.content))
            }
            index += 2
        }
        return messages
    }

    private func completeTurn(id: UUID, assistant: ChatEntry) { endTurn(id: id, assistant: assistant) }

    /// Like the Play build a turn that did not finish stays in the conversation:
    /// 沒有完成 and its reason, saved with it. The input bar stays empty. A fixed
    /// reason is kept as written and shown in the interface language
    /// (AppLocalizer.stored), like the App's other stored messages.
    private func failTurn(id: UUID, reason: String) {
        endTurn(id: id, assistant: ChatEntry(role: "assistant", content: reason, outcome: .failed))
    }

    /// A named model failure (ModelErrorCopy) is kept in the interface language
    /// of the moment, like the Play build keeps its outcome text.
    private func failTurn(id: UUID, text: AppText) {
        let shown = AppLocalizer(language: interfaceLanguage()).text(text)
        endTurn(id: id, assistant: ChatEntry(role: "assistant", content: shown, outcome: .failed))
    }

    /// The user stopped the turn: 已停止。 stays in the conversation, like the Play build.
    private func stopTurn(id: UUID) {
        endTurn(id: id, assistant: ChatEntry(role: "assistant", content: Self.stoppedMarker, outcome: .cancelled))
    }

    private func endTurn(id: UUID, assistant: ChatEntry) {
        guard requestID == id else { return }
        if let turn = pendingTurn, turn.requestID == id, entries.last?.id == turn.user.id {
            archiveTurn(turn, assistant: assistant)
            entries.append(assistant)
        }
        replyPreview = nil
        finish(id: id)
    }

    /// Saves the whole conversation with this turn. Conversations that gave way
    /// for it (oldest, never pinned) take their attachment files with them.
    /// The whole conversation with this turn answered by `assistant`.
    private func archivedRecord(_ turn: PendingTurn, assistant: ChatEntry) throws -> ArchivedConversation {
        guard let destination = turn.destination else { throw ConversationArchiveError.invalidData }
        let all = entries + [assistant]
        guard all.count % 2 == 0 else { throw ConversationArchiveError.invalidData }
        let turns = try stride(from: 0, to: all.count, by: 2).map { index in
            try ArchivedConversationTurn(userID: all[index].id, assistantID: all[index + 1].id,
                userText: all[index].content, assistantText: all[index + 1].content, pdf: all[index].pdf,
                attachments: all[index].attachments.map { try $0.archived() }, outcome: all[index + 1].outcome)
        }
        return try ArchivedConversation(id: turn.archiveID, destination: destination, updatedAt: Date(), turns: turns)
    }

    /// The app left the screen with a reply still arriving. iOS may suspend or close it
    /// before the reply ends (Android keeps a foreground service), so the turn is saved
    /// now: what has arrived with a note that it did not finish, or 沒有完成 when nothing
    /// has. A reply that then finishes replaces it, since the turn's prior becomes this save.
    func checkpointPendingTurn() {
        guard isSubmitting, let turn = pendingTurn, checkpointedRequestID != turn.requestID, let archive,
              entries.last?.id == turn.user.id else { return }
        let words = AppLocalizer(language: interfaceLanguage())
        let arrived = replyPreview?.id == turn.requestID ? (replyPreview?.text ?? "") : ""
        let assistant = arrived.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ChatEntry(role: "assistant", content: words.text(.chatReplyClosedReason), outcome: .failed)
            : ChatEntry(role: "assistant", content: arrived + "\n\n" + words.text(.chatReplyClosedNote))
        do {
            let record = try archivedRecord(turn, assistant: assistant)
            let evicted = try archive.save(record, expected: turn.prior)
            pendingTurn?.prior = record
            checkpointedRequestID = turn.requestID
            deleteAttachments(ofEvicted: evicted)
        } catch {
            // The final save still tries; nothing else depends on this one.
        }
    }

    private func archiveTurn(_ turn: PendingTurn, assistant: ChatEntry) {
        guard let archive else { return }
        pendingArchiveSave = nil
        do {
            let record = try archivedRecord(turn, assistant: assistant)
            pendingArchiveSave = (record, turn.prior)
            let evicted = try archive.save(record, expected: turn.prior)
            pendingArchiveSave = nil
            archiveNotice = nil
            deleteAttachments(ofEvicted: evicted)
        } catch {
            archiveNotice = Self.archiveSaveFailure
        }
    }

    /// Conversations that gave way for a save take their attachment files with
    /// them, except files a remaining branch still shows.
    private func deleteAttachments(ofEvicted evicted: [UUID]) {
        guard !evicted.isEmpty, let archive else { return }
        let referenced = ChatAttachmentStore.referencedFolders(in: archive.state.conversations)
        for gone in evicted { attachmentStore.deleteConversation(gone.uuidString, keeping: referenced) }
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

    private func completePlain(messages input: [ModelMessage], configuration: ModelConfiguration,
                               key: String, client: any ChatModelClient, requestID id: UUID, generation: UUID,
                               skillIndex: String?? = nil, utterance: String = "",
                               webOffer: String? = nil, mcpOffer: String? = nil) async throws -> ChatPathReply {
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        // One system message: the skill tools offer, the web task offer and the
        // MCP catalog when there are any, then Play's identity line and safety
        // rules (AISafetyRules).
        let offer = Self.plainChatOffer(skills: skillIndex.map { ChatSkillPrompts.entry(index: $0, plainChat: true, mcpOffered: mcpOffer != nil) },
                                        web: webOffer, mcp: mcpOffer)
        let messages = [AISafetyRules.systemMessage(instructions: offer)] + input
        // A reply that is exactly one skill tool command starts the skill tools
        // step; one that is exactly a web entry command starts a web task; one
        // that is exactly an MCP command starts the MCP step with it.
        func finished(_ text: String) async throws -> ChatPathReply {
            if mcpOffer != nil, let command = MCPConversationEntry.command(in: text) {
                return .mcp(MCPConversationEntry(command: command), memory: nil)
            }
            guard skillIndex != nil, ChatSkillCommand.parseEntry(text) != nil else { return .plain(text, allowsWeb: webOffer != nil) }
            // With MCP tools offered the skill tools run inside the MCP step.
            if mcpOffer != nil { return .mcp(MCPConversationEntry(command: ChatSkillCommand.unfenced(text)), memory: nil) }
            return .answer(try await runSkillTools(entryRaw: text, conversation: input, utterance: utterance, memoryOn: false,
                                                   generation: generation, configuration: configuration, key: key,
                                                   client: client, requestID: id))
        }
        guard let streaming = client as? any StreamingChatModelClient else {
            return try await finished(try await client.complete(messages: messages, configuration: configuration, apiKey: key))
        }
        // A reply opening with "{" or a code fence may be a skill, web or MCP
        // command: it is shown only once it turns out to be an answer.
        let holdsAtStart: Bool? = skillIndex == nil && webOffer == nil && mcpOffer == nil ? false : nil
        var holds = holdsAtStart, request = messages
        var text = "", bytes = 0, resent = false, nudged = false
        while true {
            do {
                for try await delta in streaming.stream(messages: request, configuration: configuration, apiKey: key) {
                    try Task.checkCancellation()
                    guard requestID == id else { throw CancellationError() }
                    guard delta.utf8.count <= ChatReplyPreview.maximumUTF8Bytes - bytes else {
                        throw HTTPChatModelError.responseTooLarge
                    }
                    guard !delta.isEmpty else { continue }
                    bytes += delta.utf8.count; text += delta
                    if holds == nil, let first = text.first(where: { !$0.isWhitespace }) { holds = first == "{" || first == "`" }
                    if holds == false { replyPreview = ChatReplyPreview(id: id, text: text, phase: .receiving) }
                }
                break
            } catch HTTPStreamFallbackError.usageOptionUnsupported where !resent && bytes == 0 {
                // Only the usage option was refused, before any text. The client
                // now leaves it out for this endpoint and model: resend once.
                resent = true
                try Task.checkCancellation()
                guard requestID == id else { throw CancellationError() }
            } catch HTTPChatModelError.truncatedResponse where !nudged {
                // Like Play's AgentLoop (TurnPolicy.afterEmpty, truncated): a reply the
                // output limit cut is not an answer yet; ask once for a shorter one.
                nudged = true
                try Task.checkCancellation()
                guard requestID == id else { throw CancellationError() }
                if !text.isEmpty { request.append(ModelMessage(role: "assistant", content: text)) }
                request.append(ModelMessage(role: "user", content: Self.truncatedReplyNudge))
                text = ""; bytes = 0; holds = holdsAtStart; replyPreview = nil
            } catch HTTPChatModelError.truncatedResponse where holds == false && !text.isEmpty {
                // Cut again: keep the text already on screen, marked as cut off.
                try Task.checkCancellation()
                guard requestID == id else { throw CancellationError() }
                let note = AppLocalizer(language: interfaceLanguage()).text(.chatReplyTruncatedNote)
                return .answer(text + "\n\n" + note)
            }
        }
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        return try await finished(text)
    }

    /// The app left the screen. A reply that is still arriving may be cut when
    /// iOS suspends the app (keptReply).
    func appLeftScreen() {
        if isSubmitting { requestLeftScreen = requestID }
    }

    /// iOS suspends the app soon after it leaves the screen, which can cut a
    /// streaming reply; Android keeps the task running in a foreground service.
    /// For a reply that was arriving when the app left the screen, the text
    /// already on screen stays, marked as cut off, instead of the whole reply
    /// failing with 網路連線失敗. Any other cut stays 沒有完成, like Play.
    private func keptReply(after error: Error, requestID id: UUID) -> String? {
        guard requestLeftScreen == id,
              let failure = error as? HTTPChatModelError, failure == .transportFailure || failure == .timedOut,
              let preview = replyPreview, preview.id == id,
              !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return preview.text + "\n\n" + AppLocalizer(language: interfaceLanguage()).text(.chatReplyInterruptedNote)
    }

    /// Play's truncated_reply nudge (prompts/feedback/loop.md) without the tool clause.
    static let truncatedReplyNudge = "Your reply was cut off by the output limit before it was complete. "
        + "Reply again with a shorter final answer."

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
        return reason + "已收到的工具結果保留；沒有自動重送操作。"
    }

    func cancel() {
        // Like Android, a stopped web task still leaves its round in the
        // conversation; the request finishes and writes it. Learning stays
        // as it is: a new learning generation would refuse to publish the round.
        if let webTask, webTask.isRunning { webTask.stop(); return }
        learning.cancelLearning()
        guard let id = requestID else { return }
        if isMCPRun { updateMCPDiagnostics(failure: "cancelled") }
        request?.cancel()
        // Like the Play build: 已停止。 stays in the conversation, saved with it.
        stopTurn(id: id)
    }

    /// Stops the request while its MCP step runs: the app is leaving the
    /// screen, or a server's connection or tool choice changed. A plain reply,
    /// a web task or a skill step goes on.
    func cancelMCP(leavingScreen: Bool = false) {
        guard isMCPRun else { return }
        guard leavingScreen, let id = requestID else { cancel(); return }
        updateMCPDiagnostics(failure: "cancelled")
        request?.cancel()
        // Not the person's 已停止。: iOS stops MCP work in the background, so the turn says why.
        failTurn(id: id, text: .chatMcpLeftScreen)
    }

    // MARK: Web tasks from chat

    /// The plain chat's one offer: the skill tools first, then the web task
    /// commands, then the MCP catalog.
    static func plainChatOffer(skills: String?, web: String?, mcp: String? = nil) -> String? {
        let offers = [skills, web, mcp].compactMap { $0 }
        return offers.isEmpty ? nil : offers.joined(separator: "\n")
    }

    private static func webEntry(_ environment: ChatWebTaskEnvironment) -> UserProfileChatSkillEntry {
        UserProfileChatSkillEntry(instructions: ChatWebTaskPrompts.entryInstructions(searchTemplate: environment.searchTemplate),
                                  accepts: { (try? ChatWebCommand.parseEntry($0)) != nil })
    }

    /// Runs the web task a reply asked for. Like Android there is no overall
    /// time limit.
    private func runWebTask(entry: ChatWebCommand, raw: String, conversation: [ModelMessage], client: any ChatModelClient,
                            configuration: ModelConfiguration, key: String, environment: ChatWebTaskEnvironment,
                            requestID id: UUID) async -> ChatWebTaskResult {
        deadline?.cancel(); deadline = nil
        replyPreview = nil
        let task = ChatWebTaskSession(client: client, configuration: configuration, apiKey: key, environment: environment)
        webTask = task
        return await task.run(conversation: conversation, entry: entry, entryRaw: raw)
    }

    /// The scene changed: a web task pauses in the background and goes on
    /// when the app is active again; .inactive changes nothing.
    func webTaskScenePhaseChanged(isActive: Bool, isBackground: Bool) {
        webTask?.scenePhaseChanged(isActive: isActive, isBackground: isBackground)
    }

    /// Android leaves the finished task's small view up for three seconds.
    private func retireWebTask() {
        guard let task = webTask, !task.isRunning else { return }
        Task { @MainActor [weak self, weak task] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, let task, self.webTask === task else { return }
            self.webTask = nil
            task.tab.close()
        }
    }

    private func completeWithProfile(messages: [ModelMessage], utterance: String,
                                     state: UserProfileState, memoryState: MemoryState, generation: UUID,
                                     configuration: ModelConfiguration, key: String,
                                     client: any ChatModelClient, requestID: UUID,
                                     skillIndex: String?? = nil, web: UserProfileChatSkillEntry? = nil,
                                     mcp: String? = nil) async throws -> ChatPathReply {
        let skillEntry = skillIndex.map {
            UserProfileChatSkillEntry(instructions: ChatSkillPrompts.entry(index: $0, plainChat: false, mcpOffered: mcp != nil),
                                      accepts: { ChatSkillCommand.parseEntry($0) != nil })
        }
        let mcpEntry = mcp.map {
            UserProfileChatSkillEntry(instructions: $0, accepts: { MCPConversationEntry.command(in: $0) != nil })
        }
        let flow = try UserProfileChatFlow(messages: messages, skillEntry: skillEntry, webEntry: web, mcpEntry: mcpEntry)
        var memoryRun = MemoryToolRun(state: memoryState, utterances: [utterance])
        defer { flow.cancel() }
        /// The model reads why a command was refused and still answers the user.
        func refuse(_ toolName: String, _ error: Error) throws {
            guard let refusal = LocalToolRefusal.resultJSON(for: error) else { throw error }
            localCommandRefusedRequestID = requestID
            try flow.recordRefused(toolName: toolName, resultJSON: refusal)
        }
        /// What the chat did so far, for the MCP step that goes on from here.
        func continuingInMCP(command: String) -> MCPConversationEntry {
            MCPConversationEntry(command: command, exchange: flow.exchange, modelCalls: flow.modelCalls,
                                 searchedLocally: flow.searchedMemory, mutatedLocally: flow.didCommit,
                                 refusedLocally: flow.localCommandRefused)
        }
        while true {
            // Like the Play build, learning data changed during the reply,
            // by the user or by the model's own tool call, never stops it.
            let step = try await flow.advance(client: client, configuration: configuration, apiKey: key,
                                              validateState: { [weak self] in
                guard let self, self.requestID == requestID else { throw CancellationError() }
                try Task.checkCancellation()
            }) { [weak self] answer in
                guard let self, self.requestID == requestID, !Task.isCancelled else { return }
                self.replyPreview = answer.map { ChatReplyPreview(id: requestID, text: $0, phase: .receiving) }
            }
            try Task.checkCancellation()
            guard self.requestID == requestID else { throw CancellationError() }
            switch step {
            case .answer(let answer): return .answer(answer)
            case .skillEntry(let json):
                // With MCP tools offered the skill tools run inside the MCP step.
                if mcp != nil { return .mcp(continuingInMCP(command: ChatSkillCommand.unfenced(json)), memory: memoryRun) }
                flow.cancel()
                return .answer(try await runSkillTools(entryRaw: json, conversation: messages, utterance: utterance, memoryOn: true,
                                                       generation: generation, configuration: configuration, key: key, client: client, requestID: requestID))
            case .webEntry(let json):
                // The flow accepted it with this same validator.
                return .web(try ChatWebCommand.parseEntry(json), raw: ChatWebCommand.unfenced(json))
            case .mcpEntry(let json):
                // The MCP step goes on from here: what the flow did and the
                // local search and change it already used come along.
                return .mcp(continuingInMCP(command: MCPConversationEntry.command(in: json) ?? json), memory: memoryRun)
            case .proposedEdit(let arguments):
                do {
                    guard learning.available, learning.memory.preferences.useMemory,
                          learning.generation == generation, learning.profile.revision == state.revision else {
                        throw UserProfileToolError.staleRevision
                    }
                    // Only the actual draft sent for this run is evidence. Context,
                    // old messages and model replies cannot authorize an edit.
                    let proposal = try UserProfileToolRequest.parse(arguments).prepare(state: state, utterances: [utterance])
                    // Like the Play build, profile_edit applies without a review.
                    try flow.validateReview()
                    let receipt = try learning.commitProfileTool(proposal, expectedGeneration: generation)
                    profileReceipt = receipt // Retained even if the next model call fails.
                    profileReceiptRequestID = requestID
                    try flow.recordCommitted(entryID: receipt.id)
                } catch { try refuse("profile_edit", error) }
            case .memorySearch(let arguments):
                do {
                    try validateMemoryRun(memoryRun, generation: generation)
                    let found = try memoryRun.search(argumentsJSON: arguments)
                    try flow.recordMemorySearchResult(found.resultJSON())
                } catch { try refuse("memory_search", error) }
            case .proposedMemoryChange(let toolName, let arguments):
                do {
                    try validateMemoryRun(memoryRun, generation: generation)
                    let review = try memoryRun.prepare(toolName: toolName, argumentsJSON: arguments)
                    // Memory tools also apply directly, with an undo note in the chat.
                    try flow.validateReview()
                    let receipt = try learning.commitMemoryTool(review, expectedGeneration: generation,
                        conversationID: conversationID)
                    memoryReceipt = receipt
                    memoryReceiptRequestID = requestID
                    if receipt.note.kind == .forgot { memoryForgotRequestID = requestID }
                    try flow.recordMemoryCommitted(toolName: toolName, resultJSON: receipt.resultJSON())
                } catch { try refuse(toolName, error) }
            }
        }
    }

    // MARK: Skill tools in ordinary chat (Play's skill_search, skill_read, skill_save)

    private static let bundledSkills: BundledSkillCatalog? = try? BundledSkillCatalog.bundled()

    /// The bundled skills plus the user's personal skills in use, read fresh.
    func chatSkillCatalog() -> ChatSkillCatalog {
        ChatSkillCatalog(bundled: Self.bundledSkills, skills: learning.available ? learning.skills : SkillsState())
    }

    /// Tool names a saved skill may mention: this chat's tools, like Play's run
    /// tool list (the skill tools and the web task commands), plus the browser
    /// research tools existing iOS skills use.
    static func chatSkillToolNames(memoryOn: Bool) -> Set<String> {
        ChatSkillCommand.toolNames.union(BrowserSession.toolNames).union(ChatWebCommand.toolNames)
            .union(memoryOn ? ["memory_search", "memory_save", "memory_edit", "profile_edit"] : [])
    }

    private func makeSkillToolRun(conversation: [ModelMessage], utterance: String, memoryOn: Bool,
                                  generation: UUID, requestID id: UUID) -> ChatSkillToolRun {
        let toolNames = Self.chatSkillToolNames(memoryOn: memoryOn)
        return ChatSkillToolRun(conversation: conversation,
            catalog: { [weak self] in self?.chatSkillCatalog() ?? ChatSkillCatalog(bundled: nil, skills: SkillsState()) },
            utterances: [utterance],
            save: { [weak self] markdown, version in
                guard let self, self.requestID == id else { throw CancellationError() }
                // The model's own save, like Play's: it keeps this request going.
                let receipt = try self.learning.commitChatSkillSave(markdown, version: version, expectedGeneration: generation,
                                                                    availableToolNames: toolNames,
                                                                    builtinNames: self.chatSkillCatalog().builtinNames)
                self.skillSavedRequestID = id
                return receipt
            },
            onStep: { [weak self] step in
                guard let self, self.requestID == id else { return }
                self.skillStep = step
            })
    }

    private func runSkillTools(entryRaw: String, conversation: [ModelMessage], utterance: String, memoryOn: Bool,
                               generation: UUID, configuration: ModelConfiguration, key: String,
                               client: any ChatModelClient, requestID id: UUID) async throws -> String {
        guard let entry = ChatSkillCommand.parseEntry(entryRaw) else { throw ChatSkillRunError.invalidCommand }
        // Like Play there is no fixed chat deadline once tools run; the step keeps
        // its own call and time limits.
        deadline?.cancel(); deadline = nil
        replyPreview = nil
        let run = makeSkillToolRun(conversation: conversation, utterance: utterance, memoryOn: memoryOn,
                                   generation: generation, requestID: id)
        defer {
            pendingSkillLearning = ChatSkillLearningInput(requestID: id, used: run.usedSkills, completedTools: run.completedTools)
        }
        return try await run.run(entry: entry, entryRaw: entryRaw, client: client, configuration: configuration, apiKey: key,
                                 validateState: { [weak self] in
            guard let self, self.requestID == id else { throw CancellationError() }
        })
    }

    private func validateMemoryRun(_ run: MemoryToolRun, generation: UUID) throws {
        guard learning.available, learning.memory.preferences.useMemory,
              learning.generation == generation, learning.memory.revision == run.baseRevision else {
            throw MemoryToolError.staleRevision
        }
    }

    private static func profileFailureMessage(_ error: Error) -> String? {
        if (error as? LearningFileError) == .busy {
            return "學習資料正在其他位置儲存；本次修改未儲存。請稍後重新確認。"
        }
        if (error as? LearningFileError) == .conflict {
            return "學習資料已變更；本次對話已停止。請重新讀取資料並再次確認。"
        }
        if error is LearningFileError {
            return "學習資料無法儲存，這次修改未發布；原有資料保留，請確認裝置儲存狀態後再試。"
        }
        if error is MemoryToolError || error is MemoryError {
            return "記憶工具未通過來源、目標或資料狀態檢查，已停止。已完成的儲存會另外顯示。"
        }
        if error is UserProfileToolError || error is UserProfileError || error is UserProfileChatError {
            return "個人檔案工具未通過檢查或已超過執行限制，已停止。已完成的儲存會另外顯示。"
        }
        return nil
    }

    /// The MCP step of a request: MCPConversationRunner over every connected
    /// server's catalog, starting with the chat's first MCP command. Like the
    /// Play build, selected tools and offered resources run with no per-call
    /// approval: the tool selection in MCP settings is the limit. Like Android's
    /// single tool list the skill tools run inside this step, between MCP calls.
    /// The model may end it with a web task, which then gets the MCP results.
    private func runMCP(entry: MCPConversationEntry, catalog: MCPChatCatalog, messages: [ModelMessage],
                        utterance: String, profileState: UserProfileState, memoryRun: MemoryToolRun,
                        generation: UUID, allowsLearning: Bool, configuration: ModelConfiguration,
                        key: String, client: any ChatModelClient, requestID: UUID,
                        web: ChatWebTaskEnvironment?) async throws -> ChatPathReply {
        guard self.requestID == requestID else { throw CancellationError() }
        // iOS stops MCP work in the background and when a server changes: a reply
        // that asks for MCP after that starts nothing.
        guard catalog.isCurrent() else { throw MCPChatChanged() }
        isMCPRun = true
        mcpReached = true
        mcpModelCalls = entry.modelCalls; mcpPhase = "starting"; updateMCPDiagnostics()
        replyPreview = nil
        startMCPDeadline(requestID: requestID)
        let turn = MCPLearningTurn(profile: profileState, memory: memoryRun, utterance: utterance, generation: generation)
        let local: MCPLocalHandler?
        if allowsLearning {
            local = { [weak self] proposal, lease in
                guard let self else { throw CancellationError() }
                return try await self.performMCPLocal(proposal, lease: lease, turn: turn, requestID: requestID)
            }
        } else { local = nil }
        var handoffs: [MCPConversationHandoff] = []
        if let web {
            handoffs.append(MCPConversationHandoff(
                instructions: ChatWebTaskPrompts.entryInstructions(searchTemplate: web.searchTemplate),
                actions: ChatWebCommand.entryActions, accepts: { (try? ChatWebCommand.parseEntry($0)) != nil }))
        }
        let skills = makeSkillToolRun(conversation: [], utterance: utterance, memoryOn: allowsLearning,
                                      generation: generation, requestID: requestID)
        let hostTools = MCPConversationHostTools(instructions: ChatSkillPrompts.insideMCP(index: chatSkillCatalog().index()),
            actions: ChatSkillCommand.toolNames, accepts: { ChatSkillCommand.parseEntry($0) != nil },
            run: { raw in try await MainActor.run { skills.perform(try ChatSkillCommand.parse(raw)) } })
        defer {
            // The outcome judge sees every tool that returned success in this request.
            pendingSkillLearning = ChatSkillLearningInput(requestID: requestID, used: skills.usedSkills,
                                                          completedTools: mcpCompletedTools + skills.completedTools)
        }
        let result = try await MCPConversationRunner(client: client).run(
            messages: messages, configuration: configuration, apiKey: key,
            tools: catalog.catalog.tools, resources: catalog.catalog.resources, executor: catalog.catalog,
            entry: entry, handoffs: handoffs, hostTools: hostTools,
            onEvent: { [weak self] event in
                await self?.receiveMCP(event, requestID: requestID)
            }, handleLocal: local)
        guard self.requestID == requestID else { throw CancellationError() }
        // The MCP step is over: a web task after it keeps running in the
        // background like any other, and has no MCP deadline.
        isMCPRun = false
        deadline?.cancel(); deadline = nil
        if result.stopReason == .handedOff, let handoff = result.handoff {
            // The runner accepted it with this same validator.
            return .web(try ChatWebCommand.parseEntry(handoff.command), raw: ChatWebCommand.unfenced(handoff.command),
                        exchange: handoff.exchange)
        }
        guard result.stopReason == .finished, let answer = result.answer else { throw MCPChatStop(reason: result.stopReason) }
        return .answer(answer)
    }

    /// The MCP tools and resources that returned success in this request.
    private var mcpCompletedTools: [String] {
        mcpSteps.filter { !$0.isError }.map { step in
            switch step.proposal.action {
            case .callTool(let name, _): return name
            case .readResource: return "read_resource"
            }
        }
    }

    /// Local learning and the remote MCP connection are separate capabilities.
    /// Every proposal is validated against this turn's captured user utterance;
    /// remote catalogs/results cannot supply that authority or replace its IDs.
    private func performMCPLocal(_ proposal: MCPLocalProposal, lease: MCPLocalLease,
                                 turn: MCPLearningTurn, requestID: UUID) async throws -> MCPLocalOutcome {
        try lease.check()
        guard self.requestID == requestID else { throw CancellationError() }
        do { return try applyMCPLocal(proposal, turn: turn, requestID: requestID) }
        catch {
            // The model reads why it was refused and goes on with the request.
            guard let refusal = LocalToolRefusal.resultJSON(for: error) else { throw error }
            localCommandRefusedRequestID = requestID
            return .refused(json: refusal)
        }
    }

    private func applyMCPLocal(_ proposal: MCPLocalProposal, turn: MCPLearningTurn, requestID: UUID) throws -> MCPLocalOutcome {
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
            // No suspension between this lease/request check and the store's
            // generation/master/revision checks plus atomic write.
            let receipt = try learning.commitProfileTool(review, expectedGeneration: turn.generation)
            profileReceipt = receipt
            profileReceiptRequestID = requestID
            let data = try JSONEncoder().encode(receipt)
            return .committedReceipt(json: String(decoding: data, as: UTF8.self))
        case .memorySave, .memoryEdit:
            try validateMemoryRun(turn.memory, generation: turn.generation)
            let review = try turn.memory.prepare(toolName: proposal.action.rawValue,
                                                 argumentsJSON: proposal.argumentsJSON)
            let receipt = try learning.commitMemoryTool(review, expectedGeneration: turn.generation,
                                                        conversationID: conversationID)
            memoryReceipt = receipt
            memoryReceiptRequestID = requestID
            if receipt.note.kind == .forgot { memoryForgotRequestID = requestID }
            return .committedReceipt(json: try receipt.resultJSON())
        }
    }

    private func receiveMCP(_ event: MCPConversationEvent, requestID: UUID) {
        guard self.requestID == requestID else { return }
        switch event {
        case .requestingModel(let count): mcpPhase = "requestingModel"; mcpModelCalls = count
        case .correctingCommand: mcpPhase = "correctingCommand"; mcpFormatCorrections += 1
        case .executing: mcpPhase = "executing"; mcpSentCount += 1; skillStep = nil
        case .completed(let step):
            mcpPhase = "receivedResult"
            mcpSteps.append(step)
            if let catalog = mcpRequestCatalog?.catalog {
                switch step.proposal.action {
                case .callTool(let name, _):
                    if let owner = catalog.owner(ofTool: name) {
                        mcpStepOwners[step.proposal.id] = MCPStepOwner(server: owner.server, target: owner.tool)
                    }
                case .readResource(let uri):
                    if let owner = catalog.owner(ofResource: uri) {
                        mcpStepOwners[step.proposal.id] = MCPStepOwner(server: owner.server, target: owner.uri)
                    }
                }
            }
        }
        mcpActivity = "MCP 嘗試呼叫 \(mcpSentCount) 次；結果紀錄 \(mcpSteps.count) 筆；異常 \(mcpSteps.filter(\.isError).count) 筆。"
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
        guard !isSubmitting else { return }
        discardPendingAttachments()
        learning.resetConversationPresentation()
        entries = []; conversationID = UUID().uuidString
        replyPreview = nil
        pendingQuote = nil
        quoteSource = nil
        archiveNotice = nil; pendingArchiveSave = nil
        mcpActivity = nil; mcpSteps = []; mcpStepOwners = [:]; mcpSentCount = 0
        mcpUnavailableServers = []; mcpOmitted = 0
        mcpDiagnostics = nil
        profileReceipt = nil
        profileReceiptRequestID = nil
        memoryReceipt = nil
        memoryReceiptRequestID = nil
        memoryForgotRequestID = nil
        chatError = nil; chatNotice = "已開啟新對話；已確認的記憶與技能保留。"
        shownSendBlocker = nil
    }

    private func finish(id: UUID) {
        guard requestID == id else { return }
        retireWebTask()
        if pendingTurn?.requestID == id { pendingTurn = nil }
        requestStartedAt = nil
        requestID = nil
        isSubmitting = false
        isMCPRun = false
        mcpReached = false
        mcpRequestCatalog = nil
        skillStep = nil
        request = nil
        deadline?.cancel()
        deadline = nil
        chatError = nil
    }

    /// The client each provider's kind chooses: chat/completions with the key
    /// for API-key providers, Responses with the account's token for a sign-in.
    private static func providerClient(_ repository: ModelSettingsRepository) -> any ChatModelClient {
        ModelProviderClient(accounts: ModelAccountTokens(repository: repository))
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

    /// `memory` holds the search a memory chat made before its MCP step, if any.
    init(profile: UserProfileState, memory: MemoryToolRun, utterance: String, generation: UUID) {
        self.profile = profile
        self.memory = memory
        self.utterance = utterance
        self.generation = generation
    }
}

/// The server and its own tool name or resource URI behind one MCP step.
struct MCPStepOwner: Equatable {
    /// The user's name for the server; "" for an unnamed one.
    let server: String
    let target: String
}

/// The MCP connection closed or a server changed between the start of the
/// request and its first MCP command: nothing ran.
private struct MCPChatChanged: Error {
    static let message = "MCP 連線或設定在回覆時變更，已停止；沒有執行任何 MCP 工具。"
}

private struct MCPChatStop: Error {
    let reason: MCPConversationStopReason
    var message: String {
        switch reason {
        case .approvalDenied: return "你已拒絕這次呼叫，MCP 對話已停止；先前的工具結果保留。"
        case .toolError: return "工具回報錯誤，已停止；請檢視工具結果。不會自動重試。"
        case .localCallLimit: return "本次對話的記憶搜尋或修改額度已用完，已停止；先前的結果保留。"
        default: return "已達 MCP 執行限制或偵測到重複呼叫；已收到的工具結果保留。"
        }
    }
}
