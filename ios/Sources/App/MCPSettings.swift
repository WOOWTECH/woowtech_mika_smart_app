import Foundation
import Security

enum MCPSettingsError: Error, LocalizedError {
    case keychainStatus(OSStatus)
    case invalidEndpoint, invalidToken, unavailableKeychain, invalidTestNamespace, missingLiveTestEndpoint
    case invalidName, tooManyServers

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            return "MCP Keychain 存取失敗（系統代碼 \(status)）。"
        case .invalidEndpoint:
            return "請輸入完整 HTTPS MCP 端點，不可含帳密、片段或空白。查詢參數會與整個端點一起安全儲存。"
        case .invalidToken:
            return "存取權杖要是一行、不含空白的英數字與符號，最長 8 KB。"
        case .unavailableKeychain:
            return "無法存取 MCP Keychain，請解鎖裝置後再試。"
        case .invalidTestNamespace:
            return "UI 測試缺少有效的隔離命名空間；不會讀取正式設定。"
        case .missingLiveTestEndpoint:
            return "Live MCP UI 測試設定未完成，未取得私密端點。"
        case .invalidName:
            return "名稱要有 1 到 40 個字、只有一行，也不能包含伺服器網址或存取權杖。"
        case .tooManyServers:
            return "最多可以儲存 16 個 MCP 伺服器。"
        }
    }
}

protocol MCPEndpointStoring {
    func load() throws -> URL?
    func save(endpoint: String) throws
    /// Removes everything saved for the server: endpoint, access token, OAuth sign-in and tool choice.
    func remove() throws
    /// Like the Play build's optional access token, sent as a Bearer header.
    func loadToken() throws -> String?
    func hasToken() throws -> Bool
    /// nil removes the token.
    func save(token: String?) throws
    /// The server's OAuth sign-in (MCPOAuthSession as JSON); nil when it does
    /// not sign in with OAuth.
    func loadOAuth() throws -> Data?
    /// nil removes the sign-in, and with it the choice of OAuth.
    func save(oauth: Data?) throws
    /// The tools the assistant may use; nil means all of them (the Play default).
    func loadAllowedTools() throws -> [String]?
    func save(allowedTools: [String]?) throws
}

/// Test doubles that only hold an endpoint have no token or sign-in and allow every tool.
extension MCPEndpointStoring {
    func loadToken() throws -> String? { nil }
    func hasToken() throws -> Bool { try loadToken() != nil }
    func save(token: String?) throws {}
    func loadOAuth() throws -> Data? { nil }
    func save(oauth: Data?) throws {}
    func loadAllowedTools() throws -> [String]? { nil }
    func save(allowedTools: [String]?) throws {}
}

/// Where the MCP settings keep their items, by account name.
protocol MCPSecureItems {
    func read(_ account: String) throws -> Data?
    func contains(_ account: String) throws -> Bool
    func write(_ data: Data, account: String) throws
    func remove(_ account: String) throws
    func removeAll() throws
}

/// One Keychain service holds every MCP item: each server's endpoint, access
/// token, OAuth sign-in and tool choice, and the server list. FreshInstallKeychainReset
/// removes the whole service after a reinstall, so every server and sign-in goes with it.
/// No endpoint, hostname, token or secret is written to UserDefaults or diagnostic output.
struct MCPKeychainItems: MCPSecureItems {
    let service: String
    var failWrites = false

    private func query(account: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrSynchronizable as String: false]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    func read(_ account: String) throws -> Data? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MCPSettingsError.keychainStatus(status) }
        guard let data = item as? Data else { throw MCPSettingsError.unavailableKeychain }
        return data
    }

    func contains(_ account: String) throws -> Bool {
        var query = query(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw MCPSettingsError.keychainStatus(status) }
        return true
    }

    func write(_ data: Data, account: String) throws {
        guard !failWrites else { throw MCPSettingsError.unavailableKeychain }
        let query = query(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        // Update the existing item atomically; never delete the old credential first.
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw MCPSettingsError.keychainStatus(update) }
        let item = query.merging(attributes) { _, new in new }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw MCPSettingsError.keychainStatus(status) }
    }

    func remove(_ account: String) throws { try delete(query(account: account)) }

    /// Every account of the service: every server and the list.
    func removeAll() throws { try delete(query(account: nil)) }

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MCPSettingsError.keychainStatus(status)
        }
    }
}

/// Items in memory only, for checks and hosted tests; never the Keychain.
final class MCPMemoryItems: MCPSecureItems {
    private(set) var values: [String: Data] = [:]
    var failWrites = false
    init(_ values: [String: Data] = [:]) { self.values = values }
    func read(_ account: String) throws -> Data? { values[account] }
    func contains(_ account: String) throws -> Bool { values[account] != nil }
    func write(_ data: Data, account: String) throws {
        guard !failWrites else { throw MCPSettingsError.unavailableKeychain }
        values[account] = data
    }
    func remove(_ account: String) throws { values.removeValue(forKey: account) }
    func removeAll() throws { values = [:] }
}

/// One server's endpoint, access token, OAuth sign-in and tool choice: the
/// accounts "<prefix>endpoint", "<prefix>token", "<prefix>oauth" and
/// "<prefix>allowed-tools". The WHOLE webhook URL is a credential, including
/// host, path and query, and so are the access token and the sign-in's tokens
/// and client secret.
struct MCPSettingsStore: MCPEndpointStoring {
    let items: any MCPSecureItems
    /// "" for the server of the single-server version: its accounts stay as
    /// they were, so nothing is copied when the list is created.
    let prefix: String

    init(items: any MCPSecureItems, prefix: String = "") {
        self.items = items; self.prefix = prefix
    }

    /// The service's first server, where the single-server version kept it.
    init(service: String, failWrites: Bool = false) {
        self.init(items: MCPKeychainItems(service: service, failWrites: failWrites))
    }

    static let productionService = "io.woowtech.assistant.mcp-endpoint.v1"
    static let accounts = ["endpoint", "token", "oauth", "allowed-tools"]

    /// Bearer tokens are visible ASCII without spaces, so the header can never be
    /// split or extended. Home Assistant's long-lived tokens are JWTs and pass.
    static let maximumTokenBytes = 8192
    static func validateToken(_ text: String) throws -> String {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= maximumTokenBytes,
              token.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else { throw MCPSettingsError.invalidToken }
        return token
    }

    static func validate(_ text: String) throws -> URL {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !address.isEmpty, address.utf8.count <= 16_384,
              !address.unicodeScalars.contains(where: forbidden.contains),
              let parts = URLComponents(string: address),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              let url = parts.url else { throw MCPSettingsError.invalidEndpoint }
        return url
    }

    /// A private test endpoint is already a complete credential. Reject a
    /// serialized/escaped copy rather than silently connecting to a URL that
    /// URLComponents repaired or whitespace trimming changed.
    static func validateInjectedEndpoint(_ raw: String) throws -> URL {
        let url = try validate(raw)
        guard url.absoluteString == raw else { throw MCPSettingsError.invalidEndpoint }
        return url
    }

    func load() throws -> URL? {
        guard let value = try read("endpoint") else { return nil }
        return try Self.validate(value)
    }

    private func read(_ name: String) throws -> String? {
        guard let data = try items.read(prefix + name) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw MCPSettingsError.unavailableKeychain }
        return value
    }

    func save(endpoint: String) throws {
        let url = try Self.validate(endpoint)
        try items.write(Data(url.absoluteString.utf8), account: prefix + "endpoint")
    }

    /// This server's accounts only: the endpoint, access token, OAuth sign-in
    /// and tool choice. The server list and the other servers stay.
    func remove() throws {
        for name in Self.accounts { try items.remove(prefix + name) }
    }

    func loadToken() throws -> String? {
        guard let value = try read("token") else { return nil }
        return try Self.validateToken(value)
    }

    func hasToken() throws -> Bool { try items.contains(prefix + "token") }

    func save(token: String?) throws {
        guard let token else { return try items.remove(prefix + "token") }
        try items.write(Data(try Self.validateToken(token).utf8), account: prefix + "token")
    }

    /// Kept whole, ThisDeviceOnly like every item: never logged or shown.
    func loadOAuth() throws -> Data? { try items.read(prefix + "oauth") }

    func save(oauth: Data?) throws {
        guard let oauth else { return try items.remove(prefix + "oauth") }
        try items.write(oauth, account: prefix + "oauth")
    }

    func loadAllowedTools() throws -> [String]? {
        guard let data = try items.read(prefix + "allowed-tools") else { return nil }
        guard let names = try? JSONDecoder().decode([String].self, from: data) else {
            throw MCPSettingsError.unavailableKeychain
        }
        return names
    }

    func save(allowedTools: [String]?) throws {
        guard let allowedTools else { return try items.remove(prefix + "allowed-tools") }
        try items.write(try JSONEncoder().encode(allowedTools), account: prefix + "allowed-tools")
    }

    /// The App's server list: production, or one isolated UI-test namespace.
    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments,
                            environment: [String: String]? = nil) throws -> MCPServerDirectory {
        try MCPServerDirectory.makeDefault(arguments: arguments, environment: environment)
    }

    static func networkAllowed(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        let testFlags = ["-UITestNamespace", "-UITestMode", "-LiveModelUITestNamespace", "-LiveModelUITest",
                         "-LiveMCPUITest", "-LiveMCPUITestCleanup", "-LiveMCPConversationUITest"]
        if arguments.contains(where: testFlags.contains) {
            if arguments.contains("-LiveModelUITest"), arguments.contains("-LiveMCPConversationUITest"),
               !arguments.contains("-LiveModelUITestCleanup"), !arguments.contains("-UITestMode"),
               !arguments.contains("-UITestNamespace"),
               arguments.filter({ $0 == "-LiveModelUITestNamespace" }).count == 1,
               let index = arguments.firstIndex(of: "-LiveModelUITestNamespace"), arguments.indices.contains(index + 1),
               UUID(uuidString: arguments[index + 1]) != nil { return true }
            guard arguments.contains("-UITestMode"), arguments.contains("-LiveMCPUITest"),
                  !arguments.contains("-LiveMCPUITestCleanup"),
                  !arguments.contains("-LiveModelUITestNamespace"), !arguments.contains("-LiveModelUITest"),
                  arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
                  let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
                  UUID(uuidString: arguments[index + 1]) != nil else { return false }
            return true
        }
        #endif
        return true
    }
}

/// One saved MCP server, without its credentials.
struct MCPServerRecord: Codable, Equatable, Identifiable {
    let id: UUID
    /// The user's name for the server; empty for the server of the
    /// single-server version until the user names it.
    var name: String
    /// Chats use enabled servers only, like Android's switch on each server.
    var enabled: Bool
    /// The server of the single-server version keeps its original accounts.
    let legacy: Bool

    /// The server id in its tools' names (MCPToolNaming): the first eight hex
    /// digits of the id, unique among the saved servers.
    var key: String { String(id.uuidString.lowercased().prefix(8)) }
    var accountPrefix: String { legacy ? "" : "server." + id.uuidString + "." }
}

/// The saved servers, in order. The list (account "servers") lives in the same
/// Keychain service as the servers' endpoints, tokens and tool choices, never
/// in UserDefaults. The first time it is read, the server of the single-server
/// version becomes its first entry, with its endpoint, token and tool choice
/// where they already are.
struct MCPServerDirectory {
    let items: any MCPSecureItems
    static let listAccount = "servers"
    static let maximumServers = 16
    static let maximumNameLength = 40

    func load() throws -> [MCPServerRecord] {
        if let data = try items.read(Self.listAccount) {
            guard let records = try? JSONDecoder().decode([MCPServerRecord].self, from: data),
                  records.count <= Self.maximumServers, Set(records.map(\.id)).count == records.count,
                  Set(records.map(\.key)).count == records.count, records.filter(\.legacy).count <= 1 else {
                throw MCPSettingsError.unavailableKeychain
            }
            return records
        }
        guard try items.contains("endpoint") else { return [] }
        let migrated = [MCPServerRecord(id: UUID(), name: "", enabled: true, legacy: true)]
        // A failed write is tried again next time; the items have not moved.
        try? save(migrated)
        return migrated
    }

    func save(_ records: [MCPServerRecord]) throws {
        try items.write(try JSONEncoder().encode(records), account: Self.listAccount)
    }

    func store(for record: MCPServerRecord) -> MCPSettingsStore {
        MCPSettingsStore(items: items, prefix: record.accountPrefix)
    }

    /// Writes a new server's endpoint and token or OAuth choice, then the list.
    /// When any write fails, nothing of the new server is left behind.
    func add(name: String, endpoint: String, token: String?, oauth: Data? = nil,
             to records: [MCPServerRecord]) throws -> MCPServerRecord {
        guard records.count < Self.maximumServers else { throw MCPSettingsError.tooManyServers }
        let url = try MCPSettingsStore.validate(endpoint)
        let token = try token.map(MCPSettingsStore.validateToken)
        let name = try Self.validateName(name, endpoint: url.absoluteString, token: token)
        let record = Self.newRecord(name: name, existing: records)
        let store = store(for: record)
        do {
            try store.save(endpoint: url.absoluteString)
            if let token { try store.save(token: token) }
            if let oauth { try store.save(oauth: oauth) }
            try save(records + [record])
        } catch {
            try? store.remove()
            throw error
        }
        return record
    }

    /// Removes the server's own items first, then its entry: a failure keeps
    /// the entry, so the server can be removed again and no secret is orphaned.
    func remove(_ record: MCPServerRecord, from records: [MCPServerRecord]) throws -> [MCPServerRecord] {
        try store(for: record).remove()
        let remaining = records.filter { $0.id != record.id }
        try save(remaining)
        return remaining
    }

    func removeAll() throws { try items.removeAll() }

    /// One line of at most 40 characters that names neither the endpoint nor
    /// the token: the name reaches the model with each tool's description.
    static func validateName(_ text: String, endpoint: String?, token: String?) throws -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength,
              !name.unicodeScalars.contains(where: CharacterSet.newlines.union(.controlCharacters).contains) else {
            throw MCPSettingsError.invalidName
        }
        let plain = name.lowercased()
        if let endpoint, !endpoint.isEmpty, plain.contains(endpoint.lowercased()) { throw MCPSettingsError.invalidName }
        if let token, token.count >= 8, name.contains(token) { throw MCPSettingsError.invalidName }
        return name
    }

    /// A new id whose key (MCPServerRecord.key) no saved server uses.
    static func newRecord(name: String, existing: [MCPServerRecord]) -> MCPServerRecord {
        let keys = Set(existing.map(\.key))
        var record = MCPServerRecord(id: UUID(), name: name, enabled: true, legacy: false)
        while keys.contains(record.key) { record = MCPServerRecord(id: UUID(), name: name, enabled: true, legacy: false) }
        return record
    }

    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments,
                            environment: [String: String]? = nil) throws -> MCPServerDirectory {
        #if DEBUG
        let liveMCP = arguments.contains("-LiveMCPUITest")
        let cleanupMCP = arguments.contains("-LiveMCPUITestCleanup")
        let liveConversation = arguments.contains("-LiveMCPConversationUITest")
        let regular = arguments.contains("-UITestNamespace") || arguments.contains("-UITestMode") || liveMCP || cleanupMCP
        let live = arguments.contains("-LiveModelUITestNamespace") || arguments.contains("-LiveModelUITest")
        guard !(regular && live) else { throw MCPSettingsError.invalidTestNamespace }
        guard !liveConversation || (live && arguments.contains("-LiveModelUITest")) else {
            throw MCPSettingsError.invalidTestNamespace
        }
        if liveMCP || cleanupMCP {
            guard arguments.contains("-UITestMode") else { throw MCPSettingsError.invalidTestNamespace }
        }
        if regular || live {
            let flag = regular ? "-UITestNamespace" : "-LiveModelUITestNamespace"
            guard arguments.filter({ $0 == flag }).count == 1,
                  let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
                  let id = UUID(uuidString: arguments[index + 1]) else {
                throw MCPSettingsError.invalidTestNamespace
            }
            let kind = regular ? "uitest" : "liveuitest"
            let directory = MCPServerDirectory(items: MCPKeychainItems(
                service: MCPSettingsStore.productionService + "." + kind + "." + id.uuidString,
                failWrites: arguments.contains("-UITestKeychainWriteFailure")))
            if (regular && arguments.contains("-UITestResetStorage"))
                || (live && arguments.contains("-LiveModelUITestCleanup")) || cleanupMCP {
                try directory.removeAll()
            }
            // Only this explicit DEBUG mode bootstraps a real endpoint. Cleanup never
            // reads the environment, and regular UI tests cannot inherit this secret.
            if (liveMCP && !cleanupMCP) || (liveConversation && !arguments.contains("-LiveModelUITestCleanup")) {
                guard let endpoint = (environment ?? ProcessInfo.processInfo.environment)["WOOW_LIVE_MCP_URL"] else {
                    throw MCPSettingsError.missingLiveTestEndpoint
                }
                _ = try MCPSettingsStore.validateInjectedEndpoint(endpoint)
                let record = try directory.seed(MCPServerDirectory.liveServer)
                let store = directory.store(for: record)
                try store.save(endpoint: endpoint)
                // Every tool starts allowed, like the Play build. A live run against
                // a real server narrows that to its audited tools before connecting.
                if let index = arguments.firstIndex(of: "-LiveMCPAllowedTools"), arguments.indices.contains(index + 1) {
                    try store.save(allowedTools: arguments[index + 1].split(separator: ",").map(String.init))
                }
            }
            if regular && arguments.contains("-UITestMode") {
                try directory.seedFixtures(arguments: arguments)
            }
            return directory
        }
        #endif
        return MCPServerDirectory(items: MCPKeychainItems(service: MCPSettingsStore.productionService))
    }
}

#if DEBUG
extension MCPServerDirectory {
    /// The live UI tests' one server (its endpoint comes from the environment).
    static let liveServer = MCPServerRecord(id: UUID(uuidString: "0E0E0E00-0000-4000-8000-00000000117E")!,
                                            name: "Live MCP", enabled: true, legacy: false)

    /// Adds the record once; a relaunch without -UITestResetStorage keeps it.
    @discardableResult func seed(_ record: MCPServerRecord) throws -> MCPServerRecord {
        let records = try load()
        if let saved = records.first(where: { $0.id == record.id }) { return saved }
        try save(records + [record])
        return record
    }
    /// Synthetic in-process servers (UITestMCPFixture); no network is used.
    /// -UITestMCPFixture: one server. -UITestMCPServers: two servers offering the
    /// same tool name and one that is down. -UITestMCPLegacyServer: the
    /// single-server version's items, which the list then takes over.
    func seedFixtures(arguments: [String]) throws {
        if arguments.contains("-UITestMCPLegacyServer") {
            // Only before the list exists: what the single-server version left.
            guard try !items.contains(Self.listAccount) else { return }
            let legacy = MCPSettingsStore(items: items)
            try legacy.save(endpoint: MCPFixtureServer.a.endpoint.absoluteString)
            try legacy.save(token: MCPFixtureServer.legacyToken)
            // The single-server version's choice: every tool off.
            try legacy.save(allowedTools: [])
            return
        }
        let servers: [MCPFixtureServer]
        if arguments.contains("-UITestMCPServers") { servers = [.a, .b, .down] }
        else if arguments.contains("-UITestMCPFixture") { servers = [.a] }
        else { return }
        for server in servers {
            let record = try seed(server.record)
            try store(for: record).save(endpoint: server.endpoint.absoluteString)
        }
    }
}

/// The synthetic UI-test servers; UITestMCPFixture answers for each endpoint.
enum MCPFixtureServer: CaseIterable {
    case a, b, down

    var record: MCPServerRecord {
        switch self {
        case .a: return MCPServerRecord(id: UUID(uuidString: "0A11CE00-0000-4000-8000-00000000000A")!,
                                        name: "Fixture A", enabled: true, legacy: false)
        case .b: return MCPServerRecord(id: UUID(uuidString: "0B0B0B00-0000-4000-8000-00000000000B")!,
                                        name: "Fixture B", enabled: true, legacy: false)
        case .down: return MCPServerRecord(id: UUID(uuidString: "0D0D0D00-0000-4000-8000-00000000000D")!,
                                           name: "Fixture down", enabled: true, legacy: false)
        }
    }

    var endpoint: URL {
        switch self {
        case .a: return URL(string: "https://fixture.invalid/mcp")!
        case .b: return URL(string: "https://fixture-b.invalid/mcp")!
        case .down: return URL(string: "https://fixture-down.invalid/mcp")!
        }
    }

    init?(endpoint: URL) {
        guard let server = Self.allCases.first(where: { $0.endpoint.host == endpoint.host }) else { return nil }
        self = server
    }

    static let legacyToken = "fixture-legacy-token-not-a-secret"
}
#endif
