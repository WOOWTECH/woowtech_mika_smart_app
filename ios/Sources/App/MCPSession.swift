import AssistantMCP
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

/// The catalog shape MCPConversationRunner encodes for the model.
private struct MCPOfferedCatalog: Encodable {
    let tools: [MCPTool]
    let resources: [MCPResource]
}

@MainActor
final class MCPSession: ObservableObject {
    enum Phase: Equatable {
        case notConfigured, saved, connecting, discovering, connected, disconnected, cancelled, failed
        /// The app went to the background: work stopped, the catalog and tool
        /// choice stay, and the connection comes back when the app is active.
        case suspended
    }

    @Published var endpointDraft = ""
    /// Like the Play build's optional access token; never shown once saved.
    @Published var tokenDraft = ""
    @Published private(set) var hasStoredEndpoint = false
    @Published private(set) var hasStoredToken = false
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
    /// Production clients carry the saved access token; injected factories don't.
    private let tokenClientFactory: (@Sendable (URL, String?) -> any MCPDiscovering)?
    private var client: (any MCPDiscovering)?
    private var request: Task<Bool, Never>?
    private var deadline: Task<Void, Never>?
    private var requestID: UUID?
    /// The saved tool choice; nil means every tool, the Play default.
    private var allowedTools: [String]?
    private var resumeWhenActive = false

    init() {
        let store: MCPSettingsStore?
        var failure: AppText?
        do { store = try MCPSettingsStore.makeDefault() }
        catch { store = nil; failure = Self.settingsMessage(error) }
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("-UITestMode")
            && ProcessInfo.processInfo.arguments.contains("-UITestMCPFixture")
        if fixture {
            allowsNetwork = true
            clientFactory = { _ in UITestMCPFixture() }
            tokenClientFactory = nil
        } else {
            allowsNetwork = MCPSettingsStore.networkAllowed()
            clientFactory = { MCPClient(endpoint: $0) }
            tokenClientFactory = { MCPClient(endpoint: $0, token: $1) }
        }
        #else
        allowsNetwork = MCPSettingsStore.networkAllowed()
        clientFactory = { MCPClient(endpoint: $0) }
        tokenClientFactory = { MCPClient(endpoint: $0, token: $1) }
        #endif
        repository = store
        guard let store else {
            errorText = failure
            phase = .failed
            return
        }
        loadSavedState(from: store)
        // Never load the credentials into a published property or start networking here.
    }

    init(repository: any MCPEndpointStoring, allowsNetwork: Bool = true,
         clientFactory: @escaping @Sendable (URL) -> any MCPDiscovering = { MCPClient(endpoint: $0) }) {
        self.repository = repository
        self.allowsNetwork = allowsNetwork
        self.clientFactory = clientFactory
        tokenClientFactory = nil
        loadSavedState(from: repository)
    }

    private func loadSavedState(from repository: any MCPEndpointStoring) {
        do {
            hasStoredEndpoint = try repository.load() != nil
            if hasStoredEndpoint {
                hasStoredToken = try repository.hasToken()
                allowedTools = try repository.loadAllowedTools()
            }
            phase = hasStoredEndpoint ? .saved : .notConfigured
        } catch {
            errorText = Self.settingsMessage(error)
            phase = .failed
        }
    }

    deinit { request?.cancel(); deadline?.cancel() }

    var isBusy: Bool { phase == .connecting || phase == .discovering }
    var canUseInConversation: Bool { phase == .connected && (!selectedToolNames.isEmpty || !resources.isEmpty) }
    /// Like the Play build, a saved server is ready for chats without a manual
    /// connect: a chat that uses MCP connects by itself (chatConnection()).
    var isAvailableForChats: Bool { repository != nil && hasStoredEndpoint && allowsNetwork }
    /// Android lists up to 30 resource URIs in its resource_read tool.
    static let offeredResourceLimit = 30
    /// MCPConversationRunner accepts at most this many tools, in a catalog of at most this size.
    static let selectionLimit = 64
    static let catalogByteLimit = 128 * 1024
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
        guard isAvailableForChats else { throw MCPChatAvailability.notConfigured }
        guard let pending = isBusy ? request : beginConnection(keepCatalog: true) else {
            throw MCPChatAvailability.unreachable
        }
        guard await pending.value else { throw MCPChatAvailability.unreachable }
        guard canUseInConversation else { throw MCPChatAvailability.noTools }
        return try conversationConnection()
    }

    var canSave: Bool {
        let endpoint = !endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let token = !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return repository != nil && !isBusy && (endpoint || (token && hasStoredEndpoint))
    }
    private var canStartConnection: Bool {
        repository != nil && hasStoredEndpoint && !isBusy && phase != .connected && allowsNetwork
    }
    var canConnect: Bool {
        canStartConnection
            && endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var statusText: String { AppLocalizer(language: .traditionalChinese).text(statusMessage) }
    var statusMessage: AppText {
        switch phase {
        case .notConfigured: return .mcpNotConfigured
        case .saved: return .mcpSavedStatus
        case .connecting: return .mcpConnecting
        case .discovering: return .mcpDiscovering
        case .connected: return .mcpConnected
        case .disconnected: return .mcpDisconnected
        case .cancelled: return .mcpCancelled
        case .failed: return .mcpFailedStatus
        case .suspended: return .mcpSuspended
        }
    }

    /// Saves a new endpoint and/or access token. Both are checked before
    /// either is written. A different endpoint is a different server: its old
    /// token and tool choice are dropped so they never reach the new host.
    func saveEndpoint() {
        guard !isBusy, let repository else { return }
        errorText = nil
        noticeText = nil
        let endpointText = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenText = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let url = endpointText.isEmpty ? nil : try MCPSettingsStore.validate(endpointText)
            let token = tokenText.isEmpty ? nil : try MCPSettingsStore.validateToken(tokenText)
            guard url != nil || hasStoredEndpoint else { throw MCPSettingsError.invalidEndpoint }
            if let url {
                // Drop the old server's token and choice first, so a failed
                // write can never leave them with the new host.
                if (try? repository.load())?.absoluteString != url.absoluteString {
                    try repository.save(token: nil)
                    try repository.save(allowedTools: nil)
                    allowedTools = nil
                }
                try repository.save(endpoint: endpointText)
            }
            if let token { try repository.save(token: token) }
            stopWork()
            clearCatalog()
            endpointDraft = ""
            tokenDraft = ""
            hasStoredEndpoint = true
            hasStoredToken = (try? repository.hasToken()) ?? false
            phase = .saved
            resumeWhenActive = false
            noticeText = .mcpSavedNotice
        } catch {
            let tokenSaved = (try? repository.hasToken()) ?? false
            hasStoredToken = hasStoredEndpoint && tokenSaved
            errorText = Self.settingsMessage(error)
        }
    }

    func removeEndpoint() {
        guard !isBusy, let repository else { return }
        errorText = nil
        noticeText = nil
        do {
            try repository.remove()
            stopWork()
            clearCatalog()
            endpointDraft = ""
            tokenDraft = ""
            hasStoredEndpoint = false
            hasStoredToken = false
            allowedTools = nil
            resumeWhenActive = false
            phase = .notConfigured
            noticeText = .mcpRemovedNotice
        } catch { errorText = Self.settingsMessage(error) }
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
        do {
            guard let stored = try repository.load() else {
                hasStoredEndpoint = false
                phase = .notConfigured
                return nil
            }
            endpoint = stored
            token = try repository.loadToken()
            allowedTools = try repository.loadAllowedTools()
        } catch {
            phase = .failed
            errorText = Self.settingsMessage(error)
            return nil
        }
        let connection = tokenClientFactory.map { $0(endpoint, token) } ?? clientFactory(endpoint)
        let id = UUID()
        requestID = id
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
        guard phase == .connected || isBusy else { return }
        resumeWhenActive = true
        stopWork()
        phase = .suspended
        errorText = nil
        noticeText = nil
    }

    func appDidBecomeActive() {
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
