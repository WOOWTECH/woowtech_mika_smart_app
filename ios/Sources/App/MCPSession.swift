import AssistantMCP
import AssistantModels
import Combine
import Foundation

// Discovery and execution share one connected, ephemeral client.
// An execution method must not return while a detached producer could still
// begin its request. The chat context lease follows the method's lifetime,
// including cancellation. MCPClient awaits its worker and transport tasks;
// injected implementations must preserve the same completion contract.
protocol MCPDiscovering: MCPConversationExecuting {
    func initialize() async throws -> MCPServerInfo
    func listTools() async throws -> [MCPTool]
    func listResources() async throws -> [MCPResource]
    func cancel() async
}

extension MCPClient: MCPDiscovering {}

/// Why a chat could not get the MCP server, mapped to a closed chat message.
enum MCPChatAvailability: Error, Equatable {
    case notConfigured, noTools, unreachable
}

/// How a server's requests are authorized, like Android's server dialog (auth
/// token or oauth): nothing, a fixed access token, or an OAuth sign-in.
enum MCPAuthMode: String, CaseIterable {
    case none, token, oauth
}

/// Shows an OAuth sign-in page: ASWebAuthenticationSession in the App
/// (MCPSignInPage). `closed` runs when the person closes the page first.
@MainActor protocol MCPSignInBrowsing: AnyObject, Sendable {
    func open(_ url: URL, closed: @escaping @MainActor () -> Void)
    func close()
}

/// A server's OAuth sign-in in its Keychain item, for the token gate too, which
/// reads and writes it off the main actor (the Keychain is safe from any thread).
struct MCPOAuthItem: @unchecked Sendable {
    let repository: any MCPEndpointStoring

    func load() throws -> MCPOAuthSession? {
        guard let data = try repository.loadOAuth() else { return nil }
        guard let session = try? JSONDecoder().decode(MCPOAuthSession.self, from: data) else {
            throw MCPSettingsError.unavailableKeychain
        }
        return session
    }

    /// nil removes the sign-in, and with it the choice of OAuth.
    func save(_ session: MCPOAuthSession?) throws {
        try repository.save(oauth: session.map { try JSONEncoder().encode($0) })
    }

    /// A refresh's result, unless the user signed in or out meanwhile.
    func save(before: MCPOAuthSession, after: MCPOAuthSession) throws {
        guard try load() == before else { return }
        try save(after)
    }
}

/// The catalog shape MCPConversationRunner encodes for the model.
private struct MCPOfferedCatalog: Encodable {
    let tools: [MCPTool]
    let resources: [MCPResource]
}

/// One MCP server: its connection, catalog and tool choice. MCPServers keeps
/// one for each saved server.
@MainActor
final class MCPSession: ObservableObject {
    enum Phase: Equatable {
        case notConfigured, saved, connecting, discovering, connected, disconnected, cancelled, failed
        /// The app went to the background: work stopped, the catalog and tool
        /// choice stay, and the connection comes back when the app is active.
        case suspended
        /// The OAuth sign-in ran out, or the server still refused it after a
        /// refresh: the user signs in again.
        case signInRequired
    }

    @Published var endpointDraft = ""
    /// Like the Play build's optional access token; never shown once saved.
    @Published var tokenDraft = ""
    @Published private(set) var hasStoredEndpoint = false
    @Published private(set) var hasStoredToken = false
    /// How the server's requests are authorized; the page's choice until saved.
    @Published var authDraft = MCPAuthMode.none
    @Published private(set) var authMode = MCPAuthMode.none
    /// OAuth: this device's sign-in for the server. No token is ever published.
    @Published private(set) var signInStatus = MCPOAuthSession.Status.signedOut
    /// A client the user registered with the server's authorization server.
    @Published private(set) var hasUserClient = false
    @Published var clientIDDraft = ""
    @Published var clientSecretDraft = ""
    @Published private(set) var isSigningIn = false
    /// The last sign-in found no registration endpoint: the page asks for a client.
    @Published private(set) var needsUserClient = false
    @Published private(set) var phase: Phase = .notConfigured
    @Published private(set) var protocolVersion: String?
    @Published private(set) var toolNames: [String] = []
    @Published private(set) var tools: [MCPTool] = []
    /// Offered to the model read-only, without a picker, like the Play build's
    /// resource_read tool: at most 30, read without a per-call approval.
    @Published private(set) var resources: [MCPResource] = []
    @Published private(set) var selectedToolNames: Set<String> = []
    @Published var toolSearch = ""
    /// Invalidates conversation snapshots before changing the endpoint or selection.
    var onConnectionChange: (() -> Void)?
    @Published private(set) var supportsTools = false
    @Published private(set) var errorText: AppText?
    var errorMessage: String? { errorText.map { AppLocalizer(language: .traditionalChinese).text($0) } }
    @Published private(set) var noticeText: AppText?
    var notice: String? { noticeText.map { AppLocalizer(language: .traditionalChinese).text($0) } }

    let allowsNetwork: Bool
    private let repository: (any MCPEndpointStoring)?
    private let clientFactory: @Sendable (URL) -> any MCPDiscovering
    /// Production clients carry the saved access token or sign-in; injected factories don't.
    private let tokenClientFactory: (@Sendable (URL, MCPCredential?) -> any MCPDiscovering)?
    /// OAuth: the server's tokens for every connection, one refresh at a time.
    private let oauthTokens: ModelAccountTokenGate<MCPOAuthSession>?
    private let oauthHTTP: MCPOAuthHTTP
    private var signInTask: Task<Void, Never>?
    private var signInID: UUID?
    private var listener: LoopbackCallbackServer?
    private var browser: (any MCPSignInBrowsing)?
    private var client: (any MCPDiscovering)?
    private var request: Task<Bool, Never>?
    private var deadline: Task<Void, Never>?
    private var requestID: UUID?
    /// The saved tool choice; nil means every tool, the Play default.
    private var allowedTools: [String]?
    private var resumeWhenActive = false
    /// Changes whenever the connection closes or a new one starts. A chat
    /// request keeps the value it connected with (MCPServers.chatCatalog()), so
    /// nothing runs on a connection that is not the one it was offered.
    private(set) var connectionEpoch = 0

    /// A saved server; production clients carry its access token or sign-in.
    /// `oauthHTTP` is for checks; the App signs in and refreshes over `.shared`.
    init(repository: any MCPEndpointStoring, allowsNetwork: Bool,
         tokenClientFactory: @escaping @Sendable (URL, MCPCredential?) -> any MCPDiscovering,
         oauthHTTP: MCPOAuthHTTP = .shared) {
        self.repository = repository
        self.allowsNetwork = allowsNetwork
        clientFactory = { tokenClientFactory($0, nil) }
        self.tokenClientFactory = tokenClientFactory
        self.oauthHTTP = oauthHTTP
        let item = MCPOAuthItem(repository: repository)
        oauthTokens = MCPOAuth.tokenGate(http: oauthHTTP, load: { try item.load() },
                                         save: { try item.save(before: $0, after: $1) })
        loadSavedState(from: repository)
        // Never load the credentials into a published property or start networking here.
    }

    init(repository: any MCPEndpointStoring, allowsNetwork: Bool = true,
         clientFactory: @escaping @Sendable (URL) -> any MCPDiscovering = { MCPClient(endpoint: $0) }) {
        self.repository = repository
        self.allowsNetwork = allowsNetwork
        self.clientFactory = clientFactory
        tokenClientFactory = nil
        oauthTokens = nil
        oauthHTTP = .shared
        loadSavedState(from: repository)
    }

    private func loadSavedState(from repository: any MCPEndpointStoring) {
        do {
            hasStoredEndpoint = try repository.load() != nil
            if hasStoredEndpoint {
                try loadAuth(from: repository)
                allowedTools = try repository.loadAllowedTools()
            }
            authDraft = authMode
            phase = hasStoredEndpoint ? .saved : .notConfigured
        } catch {
            errorText = Self.settingsMessage(error)
            phase = .failed
        }
    }

    /// The server's way of signing in, read again from its items: an OAuth
    /// item means OAuth, else a token means a fixed token.
    private func loadAuth(from repository: any MCPEndpointStoring) throws {
        hasStoredToken = try repository.hasToken()
        let oauth = try MCPOAuthItem(repository: repository).load()
        authMode = oauth != nil ? .oauth : hasStoredToken ? .token : .none
        signInStatus = oauth?.status ?? .signedOut
        hasUserClient = oauth?.userClient == true
    }

    deinit { request?.cancel(); deadline?.cancel(); signInTask?.cancel(); listener?.close() }

    var isBusy: Bool { phase == .connecting || phase == .discovering }
    var canUseInConversation: Bool { phase == .connected && (!selectedToolNames.isEmpty || !resources.isEmpty) }
    /// Like the Play build, a saved server needs no manual connect: every chat
    /// request connects it by itself (chatConnection()).
    var canConnectForChats: Bool { repository != nil && hasStoredEndpoint && allowsNetwork }
    /// Android lists up to 30 resource URIs in its resource_read tool.
    static let offeredResourceLimit = 30
    /// MCPConversationRunner accepts at most this many tools in a catalog of at
    /// most 256 KB for all servers together (MCPCombinedCatalog); one server
    /// leaves room for the server names added to the descriptions. Every tool
    /// starts allowed, like Android, within these limits.
    static let selectionLimit = MCPCombinedCatalog.maximumTools
    static let catalogByteLimit = 224 * 1024
    /// Encoded size of each tool the runner would accept, and of the catalog
    /// without tools; measured with the catalog.
    private var toolBytes: [String: Int] = [:]
    private var emptyCatalogBytes = 0

    var visibleTools: [MCPTool] {
        let query = toolSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? tools : tools.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func selectTool(_ name: String, enabled: Bool) {
        guard tools.contains(where: { $0.name == name }), enabled != selectedToolNames.contains(name) else { return }
        if enabled {
            let wanted = tools.map(\.name).filter { selectedToolNames.contains($0) || $0 == name }
            guard fitting(wanted).count == wanted.count else { noticeText = .mcpSelectionLimit; return }
        }
        onConnectionChange?()
        if enabled { selectedToolNames.insert(name) }
        else { selectedToolNames.remove(name) }
        saveSelection()
    }

    /// The choice is kept like the Play build's allowlist: every tool (nil)
    /// until the user turns one off, then the exact names.
    private func saveSelection() {
        let names = tools.map(\.name)
        let next: [String]? = selectedToolNames == Set(fitting(names)) ? nil : names.filter(selectedToolNames.contains)
        do {
            try repository?.save(allowedTools: next)
            allowedTools = next
        } catch { errorText = Self.settingsMessage(error) }
    }

    /// Returns whether a saved or default tool had to stay off.
    private func applySavedSelection(to tools: [MCPTool]) -> Bool {
        let names = tools.map(\.name)
        let wanted = allowedTools.map { allowed in names.filter(Set(allowed).contains) } ?? names
        let chosen = fitting(wanted)
        selectedToolNames = Set(chosen)
        return chosen.count < wanted.count
    }

    /// The given tools, in server order, that one conversation accepts: each
    /// valid, at most 64, all within the catalog limit with the offered
    /// resources. Allowing every tool then can never stop every MCP chat.
    private func fitting(_ names: [String]) -> [String] {
        var total = emptyCatalogBytes
        var chosen: [String] = []
        for name in names where chosen.count < Self.selectionLimit {
            guard let bytes = toolBytes[name] else { continue }
            let next = total + bytes + (chosen.isEmpty ? 0 : 1) // A comma between tools.
            if next <= Self.catalogByteLimit { total = next; chosen.append(name) }
        }
        return chosen
    }

    /// Measures the catalog once, encoded the way MCPConversationRunner encodes it.
    private func measureCatalog() {
        emptyCatalogBytes = Self.encodedSize(MCPOfferedCatalog(tools: [], resources: resources))
            ?? Self.catalogByteLimit + 1
        toolBytes = [:]
        for tool in tools where Self.usable(tool) {
            toolBytes[tool.name] = Self.encodedSize(tool)
        }
    }

    /// Like Android's isAllowedNow, checked before each call of a chat request:
    /// the same connection, and the tool still selected or the resource offered.
    func allows(_ action: MCPConversationAction, epoch: Int) -> Bool {
        guard phase == .connected, connectionEpoch == epoch, client != nil else { return false }
        switch action {
        case .callTool(let name, _): return selectedToolNames.contains(name)
        case .readResource(let uri): return resources.contains { $0.uri == uri }
        }
    }

    /// The server was deleted: its items are gone, so nothing may use it again.
    func closeForRemoval() {
        stopWork()
        clearCatalog()
        if isSigningIn { signInTask?.cancel(); endSignIn() }
        endpointDraft = ""
        tokenDraft = ""
        clearClientDrafts()
        hasStoredEndpoint = false
        clearAuth()
        allowedTools = nil
        resumeWhenActive = false
        errorText = nil
        noticeText = nil
        phase = .notConfigured
    }

    func conversationConnection() throws -> (any MCPDiscovering, [MCPTool], [MCPResource]) {
        guard canUseInConversation, let client else { throw MCPError.notInitialized }
        return (client, tools.filter { selectedToolNames.contains($0.name) }, resources)
    }

    /// The chat's way in: uses the open connection, or connects to the saved
    /// server first, the way the Play build connects its servers when a task starts.
    func chatConnection() async throws -> (any MCPDiscovering, [MCPTool], [MCPResource]) {
        if phase == .connected, client != nil {
            guard canUseInConversation else { throw MCPChatAvailability.noTools }
            return try conversationConnection()
        }
        guard canConnectForChats else { throw MCPChatAvailability.notConfigured }
        guard let pending = isBusy ? request : beginConnection(keepCatalog: true) else {
            throw MCPChatAvailability.unreachable
        }
        guard await pending.value else { throw MCPChatAvailability.unreachable }
        guard canUseInConversation else { throw MCPChatAvailability.noTools }
        return try conversationConnection()
    }

    var canSave: Bool {
        let endpoint = !endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let token = authDraft == .token && !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let client = authDraft == .oauth && !clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A fixed token is chosen with the token itself.
        let auth = authDraft != authMode && (authDraft != .token || token)
        return repository != nil && !isBusy && !isSigningIn && (endpoint || ((token || client || auth) && hasStoredEndpoint))
    }
    private var canStartConnection: Bool {
        repository != nil && hasStoredEndpoint && !isBusy && phase != .connected && allowsNetwork
    }
    var canConnect: Bool {
        canStartConnection && !hasDrafts && authDraft == authMode && !isSigningIn
            && (authMode != .oauth || signInStatus == .signedIn)
    }
    /// What is typed on the server's page and not saved yet.
    var hasDrafts: Bool {
        [endpointDraft, tokenDraft, clientIDDraft, clientSecretDraft]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    /// 登入 saves the page's changes first, like Android's 登入 in the server dialog.
    var canSignIn: Bool {
        repository != nil && hasStoredEndpoint && authDraft == .oauth && !isBusy && !isSigningIn && allowsNetwork
            && (authMode == .oauth || canSave)
    }
    var statusText: String { AppLocalizer(language: .traditionalChinese).text(statusMessage) }
    var statusMessage: AppText {
        switch phase {
        case .notConfigured: return .mcpNotConfigured
        case .saved: return authMode == .oauth && signInStatus != .signedIn ? signInMessage : .mcpSavedStatus
        case .connecting: return .mcpConnecting
        case .discovering: return .mcpDiscovering
        case .connected: return .mcpConnected
        case .disconnected: return .mcpDisconnected
        case .cancelled: return .mcpCancelled
        case .failed: return .mcpFailedStatus
        case .suspended: return .mcpSuspended
        case .signInRequired: return signInMessage
        }
    }

    /// 尚未登入 before the first sign-in and after signing out; 需要重新登入 once one ran out.
    var signInMessage: AppText {
        if phase == .signInRequired && signInStatus != .signedOut { return .mcpSignInRequired }
        switch signInStatus {
        case .signedIn: return .mcpSignedIn
        case .signedOut: return .mcpNotSignedIn
        case .expired: return .mcpSignInRequired
        }
    }

    /// Saves a new endpoint, the way of signing in (with a token, or a client
    /// for OAuth) or both. Everything is checked before anything is written. A
    /// different endpoint is a different server: its old token, sign-in and tool
    /// choice are dropped so they never reach the new host.
    func saveEndpoint() {
        guard !isBusy, !isSigningIn, let repository else { return }
        errorText = nil
        noticeText = nil
        let endpointText = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenText = authDraft == .token ? tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let clientText = authDraft == .oauth ? clientIDDraft.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let item = MCPOAuthItem(repository: repository)
        do {
            let url = endpointText.isEmpty ? nil : try MCPSettingsStore.validate(endpointText)
            let token = tokenText.isEmpty ? nil : try MCPSettingsStore.validateToken(tokenText)
            let client = clientText.isEmpty ? nil
                : MCPOAuthSession.withUserClient(id: try MCPSettingsStore.validateClient(clientText),
                                                 secret: try MCPSettingsStore.validateClient(clientSecretDraft, optional: true))
            guard url != nil || hasStoredEndpoint else { throw MCPSettingsError.invalidEndpoint }
            if authDraft == .token, authMode != .token, token == nil { throw MCPSettingsError.invalidToken }
            if let url {
                // Drop the old server's token, sign-in and choice first, so a
                // failed write can never leave them with the new host.
                if (try? repository.load())?.absoluteString != url.absoluteString {
                    try repository.save(token: nil)
                    if try item.load() != nil { try item.save(MCPOAuthSession()) }
                    try repository.save(allowedTools: nil)
                    allowedTools = nil
                }
                try repository.save(endpoint: endpointText)
            }
            switch authDraft {
            case .none:
                try repository.save(token: nil)
                try item.save(nil)
            case .token:
                try item.save(nil)
                if let token { try repository.save(token: token) }
            case .oauth:
                try repository.save(token: nil)
                // Another client starts the sign-in over.
                if let client { try item.save(client) } else if try item.load() == nil { try item.save(MCPOAuthSession()) }
            }
            stopWork()
            clearCatalog()
            endpointDraft = ""
            tokenDraft = ""
            clearClientDrafts()
            hasStoredEndpoint = true
            try loadAuth(from: repository)
            authDraft = authMode
            phase = .saved
            resumeWhenActive = false
            noticeText = .mcpSavedNotice
        } catch {
            let tokenSaved = (try? repository.hasToken()) ?? false
            hasStoredToken = hasStoredEndpoint && tokenSaved
            if hasStoredEndpoint { try? loadAuth(from: repository) }
            errorText = Self.settingsMessage(error)
        }
    }

    func removeEndpoint() {
        guard !isBusy, !isSigningIn, let repository else { return }
        errorText = nil
        noticeText = nil
        do {
            try repository.remove()
            stopWork()
            clearCatalog()
            endpointDraft = ""
            tokenDraft = ""
            clearClientDrafts()
            hasStoredEndpoint = false
            clearAuth()
            allowedTools = nil
            resumeWhenActive = false
            phase = .notConfigured
            noticeText = .mcpRemovedNotice
        } catch { errorText = Self.settingsMessage(error) }
    }

    private func clearAuth() {
        hasStoredToken = false
        authMode = .none
        authDraft = .none
        signInStatus = .signedOut
        hasUserClient = false
        needsUserClient = false
    }

    private func clearClientDrafts() {
        clientIDDraft = ""
        clientSecretDraft = ""
    }

    // MARK: OAuth sign-in

    /// 登入 (Android McpServerStore.authorize): the page's changes are saved
    /// first; then the server's sign-in page opens in `browser` and comes back to
    /// a loopback listener (MCPOAuth.signIn). The tokens go only into the server's
    /// Keychain item, never into a published property or a log. `page` is what
    /// the browser shows at the end: nil signed in, or why not.
    func signIn(browser: any MCPSignInBrowsing, page: @escaping @Sendable (AppText?) -> String) {
        guard canSignIn, let repository else { return }
        if canSave {
            saveEndpoint()
            guard errorText == nil else { return }
        }
        let item = MCPOAuthItem(repository: repository)
        guard authMode == .oauth, let endpoint = try? repository.load(), let stored = try? item.load() else { return }
        let userClient = stored.userClient ? MCPOAuthRegistration(id: stored.clientId, secret: stored.clientSecret) : nil
        errorText = nil
        noticeText = nil
        needsUserClient = false
        isSigningIn = true
        let id = UUID()
        signInID = id
        self.browser = browser
        signInTask = Task { [weak self] in
            do {
                let listener = try await LoopbackCallbackServer.open()
                defer { listener.close() }
                guard let self, self.signInID == id else { return }
                self.listener = listener
                let session = try await MCPOAuth.signIn(
                    endpoint: endpoint, userClient: userClient, listener: listener, http: self.oauthHTTP,
                    openBrowser: { url in await browser.open(url) { [weak self] in self?.cancelSignIn() } },
                    page: { failure in page(failure.map { MCPSession.signInFailure($0) }) })
                self.finishSignIn(id, session, in: item)
            } catch {
                self?.failSignIn(id, error)
            }
        }
    }

    /// 取消登入, or the sign-in page was closed: nothing is saved.
    func cancelSignIn() {
        guard isSigningIn else { return }
        signInTask?.cancel()
        endSignIn()
        errorText = nil
        noticeText = .accountFailDenied
    }

    /// 登出: the tokens go from this device; a client the user entered stays.
    /// Like Android, the authorization server is not asked to revoke them.
    func signOut() {
        guard authMode == .oauth, !isBusy, !isSigningIn, let repository else { return }
        errorText = nil
        noticeText = nil
        let item = MCPOAuthItem(repository: repository)
        do {
            try item.save((try item.load() ?? MCPOAuthSession()).signedOutByUser())
            // No connection may keep using the tokens.
            stopWork()
            clearCatalog()
            try loadAuth(from: repository)
            phase = hasStoredEndpoint ? .saved : .notConfigured
            noticeText = .mcpSignedOutNotice
        } catch { errorText = Self.settingsMessage(error) }
    }

    private func finishSignIn(_ id: UUID, _ session: MCPOAuthSession, in item: MCPOAuthItem) {
        guard signInID == id, let repository else { return }
        endSignIn()
        do {
            try item.save(session)
            try loadAuth(from: repository)
            if phase == .signInRequired || phase == .failed { phase = .saved }
            noticeText = .mcpSignedInNotice
        } catch { errorText = Self.settingsMessage(error) }
    }

    private func failSignIn(_ id: UUID, _ error: Error) {
        guard signInID == id else { return }
        endSignIn()
        guard !(error is CancellationError) else { return }
        needsUserClient = (error as? MCPOAuthError)?.reason == .noRegistration
        errorText = Self.signInFailure(error)
    }

    private func endSignIn() {
        signInID = nil
        signInTask = nil
        listener?.close()
        listener = nil
        browser?.close()
        browser = nil
        isSigningIn = false
    }

    /// Why a sign-in did not finish; only a server's error code is named.
    nonisolated static func signInFailure(_ error: Error) -> AppText {
        guard let error = error as? MCPOAuthError else { return .accountFailNetwork }
        switch error.reason {
        case .setup: return .mcpSignInFailSetup
        case .insecure: return .accountFailIssuer
        case .noRegistration: return .mcpSignInFailNoRegistration
        case .denied where error.code == "access_denied": return .accountFailDenied
        case .registration, .denied, .mismatch, .exchange: return .accountFailRejected(code: AppLocalizer.signInCode(error.code))
        case .timedOut: return .accountFailTimedOut
        case .network: return .accountFailNetwork
        }
    }

    func connect() {
        guard canConnect else { return }
        beginConnection()
    }

    @discardableResult
    private func beginConnection(keepCatalog: Bool = false) -> Task<Bool, Never>? {
        guard canStartConnection, let repository else { return nil }
        errorText = nil
        noticeText = nil
        if !keepCatalog { clearCatalog() }
        let endpoint: URL
        let token: String?
        let credential: MCPCredential?
        do {
            guard let stored = try repository.load() else {
                hasStoredEndpoint = false
                phase = .notConfigured
                return nil
            }
            endpoint = stored
            allowedTools = try repository.loadAllowedTools()
            if let oauth = try MCPOAuthItem(repository: repository).load() {
                // The gate reads the newest tokens for every request; this one only guards the catalog.
                token = oauth.accessToken.isEmpty ? nil : oauth.accessToken
                credential = oauthTokens.map(MCPCredential.oauth)
            } else {
                token = try repository.loadToken()
                credential = token.map(MCPCredential.bearer)
            }
        } catch {
            phase = .failed
            errorText = Self.settingsMessage(error)
            return nil
        }
        let connection = tokenClientFactory.map { $0(endpoint, credential) } ?? clientFactory(endpoint)
        let id = UUID()
        requestID = id
        connectionEpoch += 1
        client = connection
        phase = .connecting
        let task = Task { [weak self] () -> Bool in
            do {
                let info = try await connection.initialize()
                try Task.checkCancellation()
                guard self?.requestID == id else { return false }
                self?.phase = .discovering
                // The native actor serializes operations, so do not issue these concurrently.
                let tools = info.capabilities.contains("tools") ? try await connection.listTools() : []
                try Task.checkCancellation()
                let resources = info.capabilities.contains("resources") ? try await connection.listResources() : []
                try Task.checkCancellation()
                // The whole webhook endpoint and the token are credentials, never model context.
                let catalogData = try JSONEncoder().encode(tools)
                let resourceData = try JSONEncoder().encode(resources)
                guard let catalogText = String(data: catalogData, encoding: .utf8),
                      !Self.reveals(catalogText, endpoint: endpoint, token: token),
                      let resourceText = String(data: resourceData, encoding: .utf8),
                      !Self.reveals(resourceText, endpoint: endpoint, token: token),
                      Set(tools.map(\.name)).count == tools.count,
                      Set(resources.map(\.uri)).count == resources.count else { throw MCPError.invalidResponse }
                guard let self, self.requestID == id else { return false }
                self.protocolVersion = info.protocolVersion
                self.supportsTools = info.capabilities.contains("tools")
                self.toolNames = tools.map { Self.displayName($0.name, endpoint: endpoint) }
                self.tools = tools
                // Skip entries the conversation runner would refuse, so one bad
                // resource cannot stop every MCP conversation.
                self.resources = Array(resources.filter(Self.offerable).prefix(Self.offeredResourceLimit))
                self.measureCatalog()
                let leftOff = self.applySavedSelection(to: tools)
                self.finish(id: id)
                self.phase = .connected
                self.noticeText = leftOff ? .mcpSelectionLimit : .mcpDiscoveryNotice
                return true
            } catch {
                guard let self, self.requestID == id else { return false }
                // Nothing used this half-open connection yet, so open chats are not invalidated.
                self.stopWork(notify: false)
                self.clearCatalog()
                if (error as? MCPError) == .signInRequired {
                    // Not a connection failure: the server's page says to sign in (again).
                    if let repository = self.repository { try? self.loadAuth(from: repository) }
                    if self.authMode == .oauth {
                        self.phase = .signInRequired
                        self.errorText = .mcpSignInRequiredError
                    } else {
                        // The server wants an OAuth sign-in, not this token or none.
                        self.phase = .failed
                        self.errorText = .mcpOAuthRequired
                    }
                    return false
                }
                self.phase = .failed
                // Never interpolate server errors, names, resource URIs, endpoint URLs or tokens.
                self.errorText = .mcpConnectionError
                return false
            }
        }
        request = task
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 90_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.stopWork(notify: false)
            self.clearCatalog()
            self.phase = .failed
            self.errorText = .mcpTimeout
        }
        return task
    }

    func cancel() {
        guard isBusy else { return }
        stopWork()
        clearCatalog()
        phase = .cancelled
        errorText = nil
        noticeText = .mcpCancelledNotice
    }

    func disconnect() {
        stopWork()
        clearCatalog()
        resumeWhenActive = false
        phase = hasStoredEndpoint ? .disconnected : .notConfigured
        errorText = nil
        noticeText = .mcpDisconnectedNotice
    }

    /// A call on the open connection failed (the server restarted, its session
    /// expired, the network dropped). Nothing is retried; the next chat
    /// connects again, like the Play build connecting for each task.
    func connectionFailed() {
        guard phase == .connected else { return }
        stopWork(notify: false)
        clearCatalog()
        phase = hasStoredEndpoint ? .saved : .notConfigured
    }

    /// The app went to the background. iOS stops the network work there, so
    /// the connection closes, but unlike a manual disconnect the catalog and
    /// tool choice stay and the connection comes back on its own.
    func appWillLeaveForeground() {
        endpointDraft = ""
        tokenDraft = ""
        clearClientDrafts()
        // A sign-in goes on: the person may be fetching a code in another app.
        guard phase == .connected || isBusy else { return }
        resumeWhenActive = true
        stopWork()
        phase = .suspended
        errorText = nil
        noticeText = nil
    }

    func appDidBecomeActive() {
        // iOS may take a suspended App's listening socket away; the authorize
        // request named this port, so listen on it again (as for ChatGPT).
        if let listener, !listener.isListening { Task { try? await listener.reopen() } }
        guard resumeWhenActive else { return }
        resumeWhenActive = false
        guard phase == .suspended else { return }
        if beginConnection(keepCatalog: true) == nil, phase == .suspended {
            phase = hasStoredEndpoint ? .saved : .notConfigured
        }
    }

    private func finish(id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        request = nil
        deadline?.cancel()
        deadline = nil
    }

    private func stopWork(notify: Bool = true) {
        if notify { onConnectionChange?() }
        connectionEpoch += 1
        requestID = nil // Invalidate before cancellation, so late replies cannot restore the UI.
        request?.cancel()
        request = nil
        deadline?.cancel()
        deadline = nil
        if let previous = client { Task { await previous.cancel() } }
        client = nil
    }

    private func clearCatalog() {
        protocolVersion = nil
        toolNames = []
        tools = []
        resources = []
        selectedToolNames = []
        toolSearch = ""
        supportsTools = false
        toolBytes = [:]
        emptyCatalogBytes = 0
    }

    private static func settingsMessage(_ error: Error) -> AppText {
        guard let error = error as? MCPSettingsError else { return .mcpSettingsError }
        return AppLocalizer.mcpSettingsError(error)
    }

    /// A catalog that echoes the endpoint or the token would put a credential
    /// in front of the model. Very short tokens are not matched, to avoid
    /// refusing a catalog over an ordinary word.
    private static func reveals(_ text: String, endpoint: URL, token: String?) -> Bool {
        let plain = text.replacingOccurrences(of: "\\/", with: "/")
        if plain.contains(endpoint.absoluteString) { return true }
        if let token, token.count >= 8, plain.contains(token) { return true }
        return false
    }

    /// The same per-resource limits MCPConversationRunner checks.
    private static func offerable(_ resource: MCPResource) -> Bool {
        !resource.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resource.name.utf8.count <= 256
            && !resource.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !resource.uri.isEmpty && resource.uri.utf8.count <= 4096 && (resource.mimeType?.utf8.count ?? 0) <= 256
    }

    /// The same per-tool limits MCPConversationRunner checks.
    private static func usable(_ tool: MCPTool) -> Bool {
        guard !tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tool.name.utf8.count <= 256,
              !tool.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (tool.description?.utf8.count ?? 0) <= 8192, case .object = tool.inputSchema,
              let schemaBytes = encodedSize(tool.inputSchema), schemaBytes <= 32 * 1024 else { return false }
        var pending: [(JSONValue, Int)] = [(tool.inputSchema, 0)]
        var nodes = 0
        while let (next, depth) = pending.popLast() {
            nodes += 1
            guard nodes <= 4096, depth <= 32 else { return false }
            switch next {
            case .object(let fields):
                guard nodes + pending.count + fields.count <= 4096,
                      fields.keys.allSatisfy({ $0.utf8.count <= 8192 }) else { return false }
                pending.append(contentsOf: fields.values.map { ($0, depth + 1) })
            case .array(let values):
                guard nodes + pending.count + values.count <= 4096 else { return false }
                pending.append(contentsOf: values.map { ($0, depth + 1) })
            case .string(let text): guard text.utf8.count <= 128 * 1024 else { return false }
            case .number(let number): guard !number.isNaN else { return false }
            default: break
            }
        }
        return true
    }

    private static func encodedSize<T: Encodable>(_ value: T) -> Int? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value))?.count
    }

    private static func displayName(_ name: String, endpoint: URL) -> String {
        let redacted = name.replacingOccurrences(of: endpoint.absoluteString, with: "（端點已隱藏）")
        let scalars = redacted.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let title = String(String.UnicodeScalarView(scalars)).prefix(160)
        return title.isEmpty ? "（未提供可顯示的名稱）" : String(title)
    }
}
