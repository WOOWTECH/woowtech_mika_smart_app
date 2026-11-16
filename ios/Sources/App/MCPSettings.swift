import Foundation
import Security

enum MCPSettingsError: Error, LocalizedError {
    case keychainStatus(OSStatus)
    case invalidEndpoint, invalidToken, unavailableKeychain, invalidTestNamespace, missingLiveTestEndpoint

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
        }
    }
}

protocol MCPEndpointStoring {
    func load() throws -> URL?
    func save(endpoint: String) throws
    /// Removes everything saved for the server: endpoint, access token and tool choice.
    func remove() throws
    /// Like the Play build's optional access token, sent as a Bearer header.
    func loadToken() throws -> String?
    func hasToken() throws -> Bool
    /// nil removes the token.
    func save(token: String?) throws
    /// The tools the assistant may use; nil means all of them (the Play default).
    func loadAllowedTools() throws -> [String]?
    func save(allowedTools: [String]?) throws
}

/// Test doubles that only hold an endpoint have no token and allow every tool.
extension MCPEndpointStoring {
    func loadToken() throws -> String? { nil }
    func hasToken() throws -> Bool { try loadToken() != nil }
    func save(token: String?) throws {}
    func loadAllowedTools() throws -> [String]? { nil }
    func save(allowedTools: [String]?) throws {}
}

/// The WHOLE webhook URL is a credential, including host, path and query, and so
/// is the access token. Both, and the tool choice, live in this Keychain service
/// (accounts "endpoint", "token", "allowed-tools"); FreshInstallKeychainReset
/// removes the whole service after a reinstall.
/// No endpoint, hostname, token or secret is written to UserDefaults or diagnostic output.
struct MCPSettingsStore: MCPEndpointStoring {
    let service: String
    var failWrites = false

    private var query: [String: Any] { query(account: "endpoint") }

    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

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
        guard let value = try read(account: "endpoint") else { return nil }
        return try Self.validate(value)
    }

    private func read(account: String) throws -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MCPSettingsError.keychainStatus(status) }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw MCPSettingsError.unavailableKeychain
        }
        return value
    }

    func save(endpoint: String) throws {
        let url = try Self.validate(endpoint)
        try write(Data(url.absoluteString.utf8), account: "endpoint")
    }

    private func write(_ data: Data, account: String) throws {
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

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MCPSettingsError.keychainStatus(status)
        }
    }

    func remove() throws {
        // Every account of the service: endpoint, token and tool choice.
        try delete([kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrSynchronizable as String: false])
    }

    func loadToken() throws -> String? {
        guard let value = try read(account: "token") else { return nil }
        return try Self.validateToken(value)
    }

    func hasToken() throws -> Bool {
        var query = query(account: "token")
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw MCPSettingsError.keychainStatus(status) }
        return true
    }

    func save(token: String?) throws {
        guard let token else { return try delete(query(account: "token")) }
        try write(Data(try Self.validateToken(token).utf8), account: "token")
    }

    func loadAllowedTools() throws -> [String]? {
        guard let value = try read(account: "allowed-tools") else { return nil }
        guard let names = try? JSONDecoder().decode([String].self, from: Data(value.utf8)) else {
            throw MCPSettingsError.unavailableKeychain
        }
        return names
    }

    func save(allowedTools: [String]?) throws {
        guard let allowedTools else { return try delete(query(account: "allowed-tools")) }
        let data = try JSONEncoder().encode(allowedTools)
        try write(data, account: "allowed-tools")
    }

    static func makeDefault(arguments: [String] = ProcessInfo.processInfo.arguments,
                            environment: [String: String]? = nil) throws -> MCPSettingsStore {
        let productionService = "io.woowtech.assistant.mcp-endpoint.v1"
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
            let store = MCPSettingsStore(service: productionService + "." + kind + "." + id.uuidString,
                                         failWrites: arguments.contains("-UITestKeychainWriteFailure"))
            if (regular && arguments.contains("-UITestResetStorage"))
                || (live && arguments.contains("-LiveModelUITestCleanup")) || cleanupMCP {
                try store.remove()
            }
            // Only this explicit DEBUG mode bootstraps a real endpoint. Cleanup never
            // reads the environment, and regular UI tests cannot inherit this secret.
            if (liveMCP && !cleanupMCP) || (liveConversation && !arguments.contains("-LiveModelUITestCleanup")) {
                guard let endpoint = (environment ?? ProcessInfo.processInfo.environment)["WOOW_LIVE_MCP_URL"] else {
                    throw MCPSettingsError.missingLiveTestEndpoint
                }
                _ = try Self.validateInjectedEndpoint(endpoint)
                try store.save(endpoint: endpoint)
                // Every tool starts allowed, like the Play build. A live run against
                // a real server narrows that to its audited tools before connecting.
                if let index = arguments.firstIndex(of: "-LiveMCPAllowedTools"), arguments.indices.contains(index + 1) {
                    try store.save(allowedTools: arguments[index + 1].split(separator: ",").map(String.init))
                }
            }
            if regular && arguments.contains("-UITestMode") && arguments.contains("-UITestMCPFixture") {
                try store.save(endpoint: "https://fixture.invalid/mcp")
            }
            return store
        }
        #endif
        return MCPSettingsStore(service: productionService)
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
