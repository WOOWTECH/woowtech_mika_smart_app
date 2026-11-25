import AssistantMCP
import Combine
import Foundation

/// The MCP tools one chat request may use: every enabled server that
/// connected in time, as one catalog (MCPServers.chatCatalog()).
struct MCPChatCatalog {
    let catalog: MCPCombinedCatalog
    /// Enabled servers that were down or too slow, by the user's names ("" for
    /// an unnamed server); this request goes on without them.
    let unavailable: [String]
    /// Whether every server's connection is still the one the catalog came
    /// from. iOS stops MCP work in the background and when a server changes.
    let isCurrent: @MainActor () -> Bool
    /// After calls kept failing, the next request connects these servers again.
    let connectionsFailed: @MainActor () -> Void

    /// What a plain or memory chat offers, or nil when nothing is selected.
    var instructions: String? { catalog.entryInstructions() }
}

/// Settings › MCP 伺服器: the saved servers, like Android's McpServerStore. Each
/// server's endpoint, access token or OAuth sign-in, and tool choice stay in the
/// Keychain (MCPServerDirectory); every chat may use the enabled ones.
@MainActor
final class MCPServers: ObservableObject {
    struct Server: Identifiable {
        let record: MCPServerRecord
        let session: MCPSession
        var id: UUID { record.id }
    }

    @Published private(set) var servers: [Server] = []
    @Published private(set) var errorText: AppText?
    @Published private(set) var noticeText: AppText?
    /// Invalidates conversation snapshots before a server's endpoint, tool
    /// choice or connection changes, or a server goes away.
    var onConnectionChange: (() -> Void)?
    let allowsNetwork: Bool
    private let directory: MCPServerDirectory?
    private let makeSession: @MainActor (MCPSettingsStore) -> MCPSession

    /// Android McpServerStore.CONNECT_BUDGET_MS: a request waits at most this
    /// long for all servers together; a later one is left out of that request.
    static let connectionBudgetNanoseconds: UInt64 = 15_000_000_000
    var connectionBudgetNanoseconds = MCPServers.connectionBudgetNanoseconds

    init() {
        var failure: AppText?
        let directory: MCPServerDirectory?
        do { directory = try MCPSettingsStore.makeDefault() }
        catch { directory = nil; failure = Self.settingsMessage(error) }
        let network: Bool
        let factory: @Sendable (URL, MCPCredential?) -> any MCPDiscovering
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = arguments.contains("-UITestMode")
            && ["-UITestMCPFixture", "-UITestMCPServers", "-UITestMCPLegacyServer"].contains(where: arguments.contains)
        if fixture {
            // The fixture never receives the access token or sign-in.
            network = true
            factory = { endpoint, _ in UITestMCPFixture(endpoint: endpoint) }
        } else {
            network = MCPSettingsStore.networkAllowed()
            factory = { MCPClient(endpoint: $0, credential: $1) }
        }
        #else
        network = MCPSettingsStore.networkAllowed()
        factory = { MCPClient(endpoint: $0, credential: $1) }
        #endif
        allowsNetwork = network
        self.directory = directory
        makeSession = { MCPSession(repository: $0, allowsNetwork: network, tokenClientFactory: factory) }
        errorText = failure
        load()
    }

    /// Isolated storage for checks and hosted tests.
    init(directory: MCPServerDirectory, allowsNetwork: Bool = true,
         clientFactory: @escaping @Sendable (URL) -> any MCPDiscovering) {
        self.directory = directory
        self.allowsNetwork = allowsNetwork
        makeSession = { MCPSession(repository: $0, allowsNetwork: allowsNetwork, clientFactory: clientFactory) }
        load()
    }

    /// Servers that already exist elsewhere, such as a harness's own sessions.
    /// Nothing can be added or removed.
    init(sessions: [(MCPServerRecord, MCPSession)]) {
        directory = nil
        allowsNetwork = sessions.allSatisfy { $0.1.allowsNetwork }
        makeSession = { MCPSession(repository: $0, allowsNetwork: false) }
        servers = sessions.map { Server(record: $0.0, session: $0.1) }
        servers.forEach(wire)
    }

    /// The fixed id harnesses give one wrapped session; its key is "00000000".
    static let singleServerID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    /// One existing session as the only server.
    convenience init(single session: MCPSession, name: String = "Synthetic MCP") {
        self.init(sessions: [(MCPServerRecord(id: Self.singleServerID, name: name, enabled: true, legacy: false), session)])
    }

    var canAddServer: Bool { directory != nil && servers.count < MCPServerDirectory.maximumServers }

    func server(id: UUID) -> Server? { servers.first { $0.id == id } }

    private func load() {
        guard let directory else { return }
        do {
            servers = try directory.load().map { Server(record: $0, session: makeSession(directory.store(for: $0))) }
            servers.forEach(wire)
        } catch { errorText = Self.settingsMessage(error) }
    }

    private func wire(_ server: Server) {
        server.session.onConnectionChange = { [weak self] in self?.onConnectionChange?() }
    }

    /// Saves a new server from the add form. Its endpoint and token are checked
    /// before anything is written; no connection request is sent, and an OAuth
    /// server is signed in on its page. Without `auth`, a typed token chooses a
    /// fixed token. The form keeps what is typed itself, so nothing typed is
    /// published here.
    @discardableResult func add(name: String, endpoint: String, auth: MCPAuthMode? = nil, token: String) -> UUID? {
        guard let directory else { return nil }
        errorText = nil; noticeText = nil
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = auth ?? (typed.isEmpty ? .none : .token)
        let token = auth == .token ? typed : ""
        do {
            // A fixed token is chosen with the token itself.
            if auth == .token, token.isEmpty { throw MCPSettingsError.invalidToken }
            let oauth = auth == .oauth ? try JSONEncoder().encode(MCPOAuthSession()) : nil
            let record = try directory.add(name: name, endpoint: endpoint, token: token.isEmpty ? nil : token,
                                           oauth: oauth, to: servers.map(\.record))
            let server = Server(record: record, session: makeSession(directory.store(for: record)))
            wire(server)
            servers.append(server)
            noticeText = .mcpServerAdded
            return record.id
        } catch {
            errorText = Self.settingsMessage(error)
            return nil
        }
    }

    /// The name reaches the model with each tool's description, so it may not
    /// name the server's endpoint or token.
    func rename(id: UUID, to name: String) -> Bool {
        guard let directory, let index = servers.firstIndex(where: { $0.id == id }) else { return false }
        errorText = nil; noticeText = nil
        let store = directory.store(for: servers[index].record)
        do {
            let checked = try MCPServerDirectory.validateName(name, endpoint: (try? store.load())?.absoluteString,
                                                              token: try? store.loadToken())
            var record = servers[index].record
            record.name = checked
            try save(replacing: record)
            noticeText = .mcpServerRenamed
            return true
        } catch {
            errorText = Self.settingsMessage(error)
            return false
        }
    }

    /// A switched-off server takes no part in chats; its settings stay.
    func setEnabled(id: UUID, _ enabled: Bool) {
        guard let server = server(id: id), server.record.enabled != enabled else { return }
        errorText = nil; noticeText = nil
        var record = server.record
        record.enabled = enabled
        do {
            try save(replacing: record)
            // A running MCP request may not keep using a server that was switched off.
            if !enabled { onConnectionChange?(); server.session.disconnect() }
        } catch { errorText = Self.settingsMessage(error) }
    }

    /// Removes only this server's Keychain items, then its entry.
    func delete(id: UUID) {
        guard let directory, let server = server(id: id), !server.session.isBusy, !server.session.isSigningIn else { return }
        errorText = nil; noticeText = nil
        do {
            _ = try directory.remove(server.record, from: servers.map(\.record))
            server.session.closeForRemoval()
            servers.removeAll { $0.id == id }
            noticeText = .mcpServerRemoved
        } catch { errorText = Self.settingsMessage(error) }
    }

    /// Android's 測試全部: connects every enabled server that is not connected.
    func testAll() {
        for server in servers where server.record.enabled && server.session.canConnect { server.session.connect() }
    }

    var canTestAll: Bool {
        allowsNetwork && servers.contains { $0.record.enabled && $0.session.canConnect }
    }

    func appWillLeaveForeground() { servers.forEach { $0.session.appWillLeaveForeground() } }

    func appDidBecomeActive() { servers.forEach { $0.session.appDidBecomeActive() } }

    private func save(replacing record: MCPServerRecord) throws {
        guard let directory, let index = servers.firstIndex(where: { $0.id == record.id }) else { return }
        var records = servers.map(\.record)
        records[index] = record
        try directory.save(records)
        servers[index] = Server(record: record, session: servers[index].session)
    }

    /// Like Android's McpServerStore.connections(): every enabled server
    /// connects at once, and the request waits for them together at most
    /// connectionBudgetNanoseconds. One that fails or is still connecting is
    /// left out and named; the others are used. A connection that finishes
    /// later stays for the next request. Nil when no enabled server has an endpoint.
    func chatCatalog() async -> MCPChatCatalog? {
        let enabled = servers.filter { $0.record.enabled && $0.session.canConnectForChats }
        guard !enabled.isEmpty else { return nil }
        let race = MCPConnectionRace(count: enabled.count)
        for (index, server) in enabled.enumerated() {
            Task { @MainActor in
                do {
                    let connection = try await server.session.chatConnection()
                    // The connection this catalog came from, read in the same actor turn.
                    race.deliver(index, .connected(connection, epoch: server.session.connectionEpoch))
                }
                catch MCPChatAvailability.noTools { race.deliver(index, .nothingSelected) }
                catch { race.deliver(index, .unavailable) }
            }
        }
        let budget = connectionBudgetNanoseconds
        let timer = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: budget) } catch { return }
            race.finish()
        }
        await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            Task { @MainActor in race.finish() }
        }
        timer.cancel()
        var offers: [MCPServerOffer] = [], unavailable: [String] = []
        var connected: [(session: MCPSession, epoch: Int)] = []
        for (index, server) in enabled.enumerated() {
            switch race.outcomes[index] {
            case .connected(let connection, let epoch)?:
                let session = server.session
                let executor = MCPCheckedExecutor(base: connection.0) { action in
                    await MainActor.run { session.allows(action, epoch: epoch) }
                }
                offers.append(MCPServerOffer(key: server.record.key, name: server.record.name,
                                             tools: connection.1, resources: connection.2, executor: executor))
                connected.append((session, epoch))
            case .nothingSelected?: break
            case .unavailable?, nil: unavailable.append(server.record.name)
            }
        }
        return MCPChatCatalog(
            catalog: MCPCombinedCatalog(servers: offers), unavailable: unavailable,
            isCurrent: { connected.allSatisfy { $0.session.phase == .connected && $0.session.connectionEpoch == $0.epoch } },
            connectionsFailed: { connected.forEach { $0.session.connectionFailed() } })
    }

    private static func settingsMessage(_ error: Error) -> AppText {
        guard let error = error as? MCPSettingsError else { return .mcpSettingsError }
        return AppLocalizer.mcpSettingsError(error)
    }
}

/// One server's executor for one chat request. A call goes ahead only on the
/// same connection, with the tool still selected or the resource still offered,
/// like Android's isAllowedNow; otherwise nothing is sent and the model reads why.
private struct MCPCheckedExecutor: MCPConversationExecuting {
    let base: any MCPConversationExecuting
    let isAllowed: @Sendable (MCPConversationAction) async -> Bool

    init(base: any MCPConversationExecuting, isAllowed: @escaping @Sendable (MCPConversationAction) async -> Bool) {
        self.base = base; self.isAllowed = isAllowed
    }

    static let refused: JSONValue = .object(["isError": .bool(true), "content": .array([.object([
        "type": .string("text"),
        "text": .string("This tool or resource is no longer allowed in the app's MCP settings, or its server disconnected; nothing was sent.")
    ])])])

    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        guard await isAllowed(.callTool(name: name, arguments: arguments)) else { return Self.refused }
        return try await base.callAuthorizedTool(name: name, arguments: arguments)
    }

    func readResource(uri: String) async throws -> JSONValue {
        guard await isAllowed(.readResource(uri: uri)) else { return Self.refused }
        return try await base.readResource(uri: uri)
    }
}

/// Collects each server's connection for one request; the first of "all
/// answered", the budget or cancellation ends the wait.
@MainActor private final class MCPConnectionRace {
    enum Outcome {
        case connected((any MCPDiscovering, [MCPTool], [MCPResource]), epoch: Int)
        /// Connected, with every tool switched off and no resource.
        case nothingSelected
        case unavailable
    }
    private(set) var outcomes: [Int: Outcome] = [:]
    private let count: Int
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(count: Int) { self.count = count }

    func deliver(_ index: Int, _ outcome: Outcome) {
        guard !finished else { return }
        outcomes[index] = outcome
        if outcomes.count == count { finish() }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }

    func wait() async {
        guard !finished else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}
