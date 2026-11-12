import AssistantMCP
import Combine
import Darwin
import Foundation

/// A reviewed marker version, never an operation, endpoint or user content.
struct MCPRecoveryReview: Identifiable, Equatable {
    fileprivate let generation: UUID
    var id: UUID { generation }
}

enum MCPRecoveryPhase { case beforeRemoval, afterRemoval, beforeRestore }
private enum MCPRecoveryError: Error { case changed, corrupt, unavailable }

/// All cooperating stores use one advisory lock for marker creation, review,
/// acknowledgement and successful-turn cleanup. A marker contains only a UUID.
@MainActor private final class MCPDispatchRecovery {
    private let url: URL
    private let recoveryProbe: (MCPRecoveryPhase) throws -> Void
    private var owner: (request: UUID, generation: UUID)?
    private static var failedClosed: Set<String> = []
    private static var retainedLocks: [String: Int32] = [:]
    init(url: URL, recoveryProbe: @escaping (MCPRecoveryPhase) throws -> Void = { _ in }) {
        self.url = url; self.recoveryProbe = recoveryProbe
    }

    var blocked: Bool {
        if Self.failedClosed.contains(url.path) { return true }
        // Another cooperating process can retain this lock after an
        // unrecoverable storage error, even if the marker could not be restored.
        let lockFD = open(url.path + ".lock", O_RDWR | O_NOFOLLOW)
        if lockFD >= 0 {
            let acquired = flock(lockFD, LOCK_EX | LOCK_NB) == 0
            if acquired { flock(lockFD, LOCK_UN) }
            close(lockFD)
            if !acquired { return true }
        } else if errno != ENOENT { return true }
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as NSError {
            return !(error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError)
        }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        guard !Self.failedClosed.contains(url.path) else { throw MCPRecoveryError.unavailable }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockFD = open(url.path + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard lockFD >= 0 else { throw MCPRecoveryError.unavailable }
        var info = stat()
        guard fstat(lockFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); throw MCPRecoveryError.unavailable }
        defer {
            if Self.failedClosed.contains(url.path) {
                // Retain the cooperative lock until process exit if even the
                // pending marker cannot be restored. Never publish success.
                Self.retainedLocks[url.path] = lockFD
            } else { flock(lockFD, LOCK_UN); close(lockFD) }
        }
        return try body()
    }

    private func syncDirectory() throws {
        let fd = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard fd >= 0 else { throw MCPRecoveryError.unavailable }
        let synced = fsync(fd) == 0
        let closed = close(fd) == 0
        guard synced, closed else { throw MCPRecoveryError.unavailable }
    }

    private func writeGeneration(_ generation: UUID, fd: Int32) throws {
        let bytes = Array(generation.uuidString.utf8)
        let written = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard written == bytes.count, fsync(fd) == 0 else { throw MCPRecoveryError.unavailable }
    }

    /// Existing f62849a markers are empty. Upgrade them under the same lock
    /// before showing a review, so a stale review cannot clear a later marker.
    private func generation(upgradeLegacy: Bool) throws -> UUID {
        let fd = open(url.path, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw errno == ENOENT ? MCPRecoveryError.changed : MCPRecoveryError.unavailable }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw MCPRecoveryError.unavailable }
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size == 0 || info.st_size == 36 else { throw MCPRecoveryError.corrupt }
        if info.st_size == 0 {
            guard upgradeLegacy else { throw MCPRecoveryError.changed }
            let value = UUID()
            try writeGeneration(value, fd: fd)
            return value
        }
        var bytes = [UInt8](repeating: 0, count: 36)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == 36, let text = String(bytes: bytes, encoding: .utf8),
              let value = UUID(uuidString: text) else { throw MCPRecoveryError.corrupt }
        return value
    }

    func reserve(_ id: UUID) throws {
        try locked {
            guard !Self.failedClosed.contains(url.path) else { throw MCPRecoveryError.unavailable }
            if let owner, owner.request == id {
                guard try generation(upgradeLegacy: false) == owner.generation else { throw MCPRecoveryError.changed }
                return
            }
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard fd >= 0 else { throw MCPRecoveryError.unavailable }
            let value = UUID()
            do { try writeGeneration(value, fd: fd) }
            catch { close(fd); throw error }
            guard close(fd) == 0 else { throw MCPRecoveryError.unavailable }
            try syncDirectory()
            owner = (id, value)
        }
    }

    func review() throws -> MCPRecoveryReview {
        try locked {
            guard !Self.failedClosed.contains(url.path) else { throw MCPRecoveryError.unavailable }
            return MCPRecoveryReview(generation: try generation(upgradeLegacy: true))
        }
    }

    private func remove(_ expected: UUID, forRecovery: Bool) throws {
        guard try generation(upgradeLegacy: false) == expected else { throw MCPRecoveryError.changed }
        if forRecovery { try recoveryProbe(.beforeRemoval) }
        // Verify the directory can be synced before removing the only marker.
        try syncDirectory()
        guard unlink(url.path) == 0 else { throw MCPRecoveryError.unavailable }
        do {
            if forRecovery { try recoveryProbe(.afterRemoval) }
            try syncDirectory()
        } catch {
            // Preserve a pending marker if the removal could not be confirmed.
            let canRestore: Bool
            do { if forRecovery { try recoveryProbe(.beforeRestore) }; canRestore = true }
            catch { canRestore = false }
            let fd = canRestore ? open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600)) : -1
            var restored = false
            if fd >= 0 {
                let wrote: Bool
                do { try writeGeneration(expected, fd: fd); wrote = true }
                catch { wrote = false }
                let closed = close(fd) == 0
                if wrote && closed { do { try syncDirectory(); restored = true } catch {} }
            }
            if !restored { Self.failedClosed.insert(url.path) }
            throw MCPRecoveryError.unavailable
        }
    }

    func acknowledge(_ review: MCPRecoveryReview) throws {
        try locked {
            guard !Self.failedClosed.contains(url.path) else { throw MCPRecoveryError.unavailable }
            try remove(review.generation, forRecovery: true)
            owner = nil
        }
    }

    func complete(_ id: UUID) {
        guard let owner, owner.request == id else { return }
        do { try locked { try remove(owner.generation, forRecovery: false) }; self.owner = nil }
        catch { /* Retain the marker or fail closed on storage failure. */ }
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
    @Published private(set) var recoveryIssue: AppText?
    @Published private(set) var recoveryNotice: AppText?

    /// Re-read the marker, rather than relying on a cached store instance.
    var unresolvedToolOutcome: Bool { dispatchRecovery?.blocked ?? true }

    func prepareToolRecovery() -> MCPRecoveryReview? {
        recoveryNotice = nil
        do {
            guard let dispatchRecovery else { throw MCPRecoveryError.unavailable }
            let review = try dispatchRecovery.review()
            recoveryIssue = nil; recoveryNotice = nil
            return review
        } catch MCPRecoveryError.corrupt { recoveryIssue = .mcpRecoveryCorrupt; return nil }
        catch MCPRecoveryError.changed { recoveryIssue = .mcpRecoveryChanged; return nil }
        catch { recoveryIssue = .mcpRecoveryStorageError; return nil }
    }

    @discardableResult func acknowledgeToolRecovery(_ review: MCPRecoveryReview) -> Bool {
        do {
            guard let dispatchRecovery else { throw MCPRecoveryError.unavailable }
            try dispatchRecovery.acknowledge(review)
            recoveryIssue = nil; recoveryNotice = .mcpRecoveryReleased; objectWillChange.send()
            return true
        } catch MCPRecoveryError.corrupt { recoveryIssue = .mcpRecoveryCorrupt }
        catch MCPRecoveryError.changed { recoveryIssue = .mcpRecoveryChanged }
        catch { recoveryIssue = .mcpRecoveryStorageError }
        objectWillChange.send()
        return false
    }

    func reserveToolDispatch(requestID: UUID) throws {
        guard let dispatchRecovery else { throw MCPError.busy }
        recoveryNotice = nil
        try dispatchRecovery.reserve(requestID)
        recoveryIssue = nil
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
        let arguments = ProcessInfo.processInfo.arguments
        let recoveryFixture: Bool
        do { recoveryFixture = try UITestMCPRecoveryConfiguration.resolve(arguments: arguments) }
        catch { preconditionFailure("Invalid isolated MCP recovery fixture arguments") }
        let fixture = arguments.contains("-UITestMode") && arguments.contains("-UITestMCPFixture")
        if fixture {
            allowsNetwork = true
            clientFactory = { _ in UITestMCPFixture(delayRecovery: recoveryFixture) }
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
         recoveryProbe: @escaping (MCPRecoveryPhase) throws -> Void = { _ in },
         clientFactory: @escaping @Sendable (URL) -> any MCPDiscovering = { MCPClient(endpoint: $0) }) {
        self.repository = repository
        self.allowsNetwork = allowsNetwork
        self.dispatchRecovery = MCPDispatchRecovery(url: recoveryURL, recoveryProbe: recoveryProbe)
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
