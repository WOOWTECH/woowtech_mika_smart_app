import Foundation

extension AppLocalizer {
    static func mcpSettingsError(_ error: MCPSettingsError) -> AppText {
        switch error {
        case .keychainStatus(let code): return .mcpKeychainStatus(code: String(code))
        case .invalidEndpoint: return .mcpInvalidEndpoint
        case .invalidToken: return .mcpInvalidToken
        case .unavailableKeychain: return .mcpKeychainUnavailable
        case .invalidTestNamespace: return .mcpInvalidNamespace
        case .missingLiveTestEndpoint: return .mcpMissingLiveEndpoint
        case .invalidName: return .mcpInvalidServerName
        case .tooManyServers: return .mcpTooManyServers
        case .invalidClient: return .mcpInvalidClient
        }
    }

    /// A sign-in server's error code as shown: short, and only the characters codes use.
    static func signInCode(_ code: String?) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard let code, !code.isEmpty, code.count <= 64, code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "unknown" }
        return code
    }
}
