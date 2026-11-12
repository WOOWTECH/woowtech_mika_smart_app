import AssistantMCP
import Combine
import Darwin
import Foundation

/// An exclusive, nonsecret marker reserved before the first remote dispatch.
/// It survives ordinary process restarts and prevents another app session from
/// silently retrying an unfinished turn. External writers bypassing this
/// protocol and storage erased by the user are outside this guarantee.
@MainActor private final class MCPDispatchRecovery {
    private let url: URL
    private var owner: UUID?
    init(url: URL) { self.url = url }

    var blocked: Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as NSError {
            return !(error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
        }
    }

    func reserve(_ id: UUID) throws {
        if owner == id { return }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw MCPError.busy }
        let flushed = fsync(fd) == 0
        let closed = close(fd) == 0
        // On any failure leave the marker in place and reject dispatch.
        guard flushed, closed else { throw MCPError.busy }
        let directoryFD = open(directory.path, O_RDONLY)
        guard directoryFD >= 0 else { throw MCPError.busy }
        let directoryFlushed = fsync(directoryFD) == 0
        let directoryClosed = close(directoryFD) == 0
        guard directoryFlushed, directoryClosed else { throw MCPError.busy }
        owner = id
    }

    func complete(_ id: UUID) {
        guard owner == id else { return }
        do { try FileManager.default.removeItem(at: url); owner = nil }
        catch { /* Failure leaves the conservative block in place. */ }
    }
}

// Discovery and execution share one explicitly connected, ephemeral client.
protocol MCPDiscovering: MCPConversationExecuting {
    func initialize() async throws -> MCPServerInfo
    func listTools() async throws -> [MCPTool]
    func listResources() async throws -> [MCPResource]
    func cancel() async
}

extension MCPClient: MCPDiscovering {}

@MainActor
final class MCPSession: ObservableObject {
    enum Phase: Equatable {
        case notConfigured, saved, connecting, discovering, connected, disconnected, cancelled, failed
    }

    @Published var endpointDraft = ""
    @Published private(set) var hasStoredEndpoint = false
    @Published private(set) var phase: Phase = .notConfigured
    @Published private(set) var protocolVersion: String?
    @Published private(set) var toolNames: [String] = []
    @Published private(set) var resourceNames: [String] = []
    @Published private(set) var tools: [MCPTool] = []
    @Published private(set) var resources: [MCPResource] = []
    @Published private(set) var selectedToolNames: Set<String> = []
    @Published private(set) var selectedResourceURIs: Set<String> = []
    @Published var toolSearch = ""
    /// Invalidates conversation snapshots before changing the endpoint or selection.
    var onConnectionChange: (() -> Void)?
    @Published private(set) var supportsTools = false
    @Published private(set) var supportsResources = false
    @Published private(set) var errorText: AppText?
    var errorMessage: String? { errorText.map { AppLocalizer(language: .traditionalChinese).text($0) } }
    @Published private(set) var noticeText: AppText?
    var notice: String? { noticeText.map { AppLocalizer(language: .traditionalChinese).text($0) } }

    let allowsNetwork: Bool
    private let repository: (any MCPEndpointStoring)?
    private let clientFactory: @Sendable (URL) -> any MCPDiscovering
    private var client: (any MCPDiscovering)?
    private var request: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var requestID: UUID?
    private let dispatchRecovery: MCPDispatchRecovery?

    /// Re-read the marker, rather than relying on a cached store instance.
    var unresolvedToolOutcome: Bool { dispatchRecovery?.blocked ?? true }

    func reserveToolDispatch(requestID: UUID) throws {
        guard let dispatchRecovery else { throw MCPError.busy }
        try dispatchRecovery.reserve(requestID)
        objectWillChange.send()
    }

    func completeToolTurn(requestID: UUID) {
        dispatchRecovery?.complete(requestID)
        objectWillChange.send()
    }

    init() {
        let recoveryURL = try? ConversationArchiveStore.location(arguments: ProcessInfo.processInfo.arguments)
            .url.deletingLastPathComponent().appendingPathComponent("mcp-unresolved-operation")
        dispatchRecovery = recoveryURL.map { MCPDispatchRecovery(url: $0) }
        #if DEBUG
        let fixture = ProcessInfo.processInfo.arguments.contains("-UITestMode")
            && ProcessInfo.processInfo.arguments.contains("-UITestMCPFixture")
        if fixture {
            allowsNetwork = true
            clientFactory = { _ in UITestMCPFixture() }
        } else {
            allowsNetwork = MCPSettingsStore.networkAllowed()
            clientFactory = { MCPClient(endpoint: $0) }
        }
        #else
        allowsNetwork = MCPSettingsStore.networkAllowed()
        clientFactory = { MCPClient(endpoint: $0) }
        #endif
        let store: MCPSettingsStore
        do {
            store = try MCPSettingsStore.makeDefault()
        } catch {
            repository = nil
            errorText = Self.settingsMessage(error)
            phase = .failed
            return
        }
        repository = store
        do {
            hasStoredEndpoint = try store.load() != nil
            phase = hasStoredEndpoint ? .saved : .notConfigured
        } catch {
            errorText = Self.settingsMessage(error)
            phase = .failed
        }
        // Never load the credential into a published property or start networking here.
    }

    init(repository: any MCPEndpointStoring, allowsNetwork: Bool = true,
         recoveryURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-recovery-" + UUID().uuidString).appendingPathComponent("marker"),
         clientFactory: @escaping @Sendable (URL) -> any MCPDiscovering = { MCPClient(endpoint: $0) }) {
        self.repository = repository
        self.allowsNetwork = allowsNetwork
        self.dispatchRecovery = MCPDispatchRecovery(url: recoveryURL)
        self.clientFactory = clientFactory
        do {
            hasStoredEndpoint = try repository.load() != nil
            phase = hasStoredEndpoint ? .saved : .notConfigured
        } catch {
            errorText = Self.settingsMessage(error)
            phase = .failed
        }
    }

    deinit { request?.cancel(); deadline?.cancel() }

    var isBusy: Bool { phase == .connecting || phase == .discovering }
    var canUseInConversation: Bool { phase == .connected && (!selectedToolNames.isEmpty || !selectedResourceURIs.isEmpty) }

    var visibleTools: [MCPTool] {
        let query = toolSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? tools : tools.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func selectTool(_ name: String, enabled: Bool) {
        guard tools.contains(where: { $0.name == name }) else { return }
        guard !enabled || selectedToolNames.count < 64 else {
            noticeText = .mcpSelectionLimit; return
        }
        onConnectionChange?()
        if enabled { selectedToolNames.insert(name) }
        else { selectedToolNames.remove(name) }
    }

    func selectResource(_ uri: String, enabled: Bool) {
        guard resources.contains(where: { $0.uri == uri }) else { return }
        guard !enabled || selectedResourceURIs.count < 64 else { return }
        onConnectionChange?()
        if enabled { selectedResourceURIs.insert(uri) }
        else { selectedResourceURIs.remove(uri) }
    }

    func conversationConnection() throws -> (any MCPDiscovering, [MCPTool], [MCPResource]) {
        guard !unresolvedToolOutcome else { throw MCPError.busy }
        guard canUseInConversation, let client else { throw MCPError.notInitialized }
        return (client, tools.filter { selectedToolNames.contains($0.name) },
                resources.filter { selectedResourceURIs.contains($0.uri) })
    }
    var canSave: Bool { repository != nil && !isBusy && !endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canConnect: Bool {
        hasStoredEndpoint && !isBusy && phase != .connected
            && endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && allowsNetwork
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
        }
    }

    func saveEndpoint() {
        guard !isBusy, let repository else { return }
        errorText = nil
        noticeText = nil
        do {
            try repository.save(endpoint: endpointDraft)
            stopWork()
            clearCatalog()
            endpointDraft = ""
            hasStoredEndpoint = true
            phase = .saved
            noticeText = .mcpSavedNotice
        } catch { errorText = Self.settingsMessage(error) }
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
            hasStoredEndpoint = false
            phase = .notConfigured
            noticeText = .mcpRemovedNotice
        } catch { errorText = Self.settingsMessage(error) }
    }

    func connect() {
        guard canConnect, let repository else { return }
        errorText = nil
        noticeText = nil
        clearCatalog()
        let endpoint: URL
        do {
            guard let stored = try repository.load() else {
                hasStoredEndpoint = false
                phase = .notConfigured
                return
            }
            endpoint = stored
        } catch {
            phase = .failed
            errorText = Self.settingsMessage(error)
            return
        }
        let connection = clientFactory(endpoint)
        let id = UUID()
        requestID = id
        client = connection
        phase = .connecting
        request = Task { [weak self] in
            do {
                let info = try await connection.initialize()
                try Task.checkCancellation()
                guard self?.requestID == id else { return }
                self?.phase = .discovering
                // The native actor serializes operations, so do not issue these concurrently.
                let tools = info.capabilities.contains("tools") ? try await connection.listTools() : []
                try Task.checkCancellation()
                let resources = info.capabilities.contains("resources") ? try await connection.listResources() : []
                try Task.checkCancellation()
                // The whole webhook endpoint is a credential, never model context.
                let catalogData = try JSONEncoder().encode(tools)
                let resourceData = try JSONEncoder().encode(resources)
                guard let catalogText = String(data: catalogData, encoding: .utf8),
                      !catalogText.replacingOccurrences(of: "\\/", with: "/").contains(endpoint.absoluteString),
                      let resourceText = String(data: resourceData, encoding: .utf8),
                      !resourceText.replacingOccurrences(of: "\\/", with: "/").contains(endpoint.absoluteString),
                      Set(tools.map(\.name)).count == tools.count,
                      Set(resources.map(\.uri)).count == resources.count else { throw MCPError.invalidResponse }
                guard let self, self.requestID == id else { return }
                self.protocolVersion = info.protocolVersion
                self.supportsTools = info.capabilities.contains("tools")
                self.supportsResources = info.capabilities.contains("resources")
                self.toolNames = tools.map { Self.displayName($0.name, endpoint: endpoint) }
                self.resourceNames = resources.map { Self.displayName($0.name, endpoint: endpoint) }
                self.tools = tools
                self.resources = resources
                self.finish(id: id)
                self.phase = .connected
                self.noticeText = .mcpDiscoveryNotice
            } catch {
                guard let self, self.requestID == id else { return }
                self.stopWork()
                self.clearCatalog()
                self.phase = .failed
                // Never interpolate server errors, names, resource URIs, or endpoint URLs.
                self.errorText = .mcpConnectionError
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 90_000_000_000) }
            catch { return }
            guard let self, self.requestID == id else { return }
            self.stopWork()
            self.clearCatalog()
            self.phase = .failed
            self.errorText = .mcpTimeout
        }
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
        phase = hasStoredEndpoint ? .disconnected : .notConfigured
        errorText = nil
        noticeText = .mcpDisconnectedNotice
    }

    private func finish(id: UUID) {
        guard requestID == id else { return }
        requestID = nil
        request = nil
        deadline?.cancel()
        deadline = nil
    }

    private func stopWork() {
        onConnectionChange?()
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
        resourceNames = []
        tools = []
        resources = []
        selectedToolNames = []
        selectedResourceURIs = []
        toolSearch = ""
        supportsTools = false
        supportsResources = false
    }

    private static func settingsMessage(_ error: Error) -> AppText {
        guard let error = error as? MCPSettingsError else { return .mcpSettingsError }
        return AppLocalizer.mcpSettingsError(error)
    }

    private static func displayName(_ name: String, endpoint: URL) -> String {
        let redacted = name.replacingOccurrences(of: endpoint.absoluteString, with: "（端點已隱藏）")
        let scalars = redacted.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let title = String(String.UnicodeScalarView(scalars)).prefix(160)
        return title.isEmpty ? "（未提供可顯示的名稱）" : String(title)
    }
}
