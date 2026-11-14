import Foundation

@main
enum MCPSettingsChecks {
    static func main() throws {
        let id = UUID().uuidString
        let regular = ["-UITestMode", "-UITestNamespace", id]
        let model = ["-LiveModelUITest", "-LiveModelUITestNamespace", id]
        let combined = model + ["-LiveMCPConversationUITest"]
        var count = 0
        func check(_ condition: Bool) {
            precondition(condition, "App MCP network isolation policy failed")
            count += 1
        }
        for args in [regular, model, regular + ["-UITestMCPFixture"],
                     combined + ["-LiveModelUITestCleanup"], combined + ["-UITestMode"],
                     combined + ["-UITestNamespace", id], combined + ["-LiveModelUITestNamespace", id],
                     ["-LiveMCPConversationUITest"], ["-LiveModelUITest", "-LiveMCPConversationUITest"]] {
            check(!MCPSettingsStore.networkAllowed(arguments: args))
        }
        check(MCPSettingsStore.networkAllowed(arguments: combined))
        check(MCPSettingsStore.networkAllowed(arguments: regular + ["-LiveMCPUITest"]))
        check(!MCPSettingsStore.networkAllowed(arguments: regular + ["-LiveMCPUITest", "-LiveMCPUITestCleanup"]))
        // Invalid flags must fail before any production Keychain access.
        for args in [["-LiveMCPConversationUITest"], ["-LiveModelUITest", "-LiveMCPConversationUITest"],
                     combined + ["-UITestMode"], combined + ["-LiveModelUITestNamespace", id]] {
            do {
                _ = try MCPSettingsStore.makeDefault(arguments: args, environment: [:])
                preconditionFailure("Invalid private test namespace was accepted")
            } catch MCPSettingsError.invalidTestNamespace { count += 1 }
        }
        // Live secrets must survive validation byte-for-byte. URLComponents
        // otherwise repairs a trailing backslash or trims a pasted prefix.
        let exact = "https://fixture.invalid/mcp/a%2Fb?token=x%2Fy+z&mode=read"
        check(try MCPSettingsStore.validateInjectedEndpoint(exact).absoluteString == exact)
        check(try MCPSettingsStore.validate(" " + exact).absoluteString == exact) // Manual paste still trims.
        let serialized = "\"\(exact)\""
        for malformed in [serialized, exact.replacingOccurrences(of: "/", with: "\\/"),
                          " " + exact, exact + "\\"] {
            do {
                _ = try MCPSettingsStore.validateInjectedEndpoint(malformed)
                preconditionFailure("A changed or serialized private endpoint was accepted")
            } catch MCPSettingsError.invalidEndpoint { count += 1 }
        }
        // Like the Play build's access token, sent as "Authorization: Bearer <token>":
        // one line of visible ASCII, so the header can never be split or extended.
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJmaXh0dXJlIn0.c2lnbmF0dXJlLXZhbHVl"
        check(try MCPSettingsStore.validateToken(jwt) == jwt)
        check(try MCPSettingsStore.validateToken("  " + jwt + "\n") == jwt) // A pasted token is trimmed.
        check(try MCPSettingsStore.validateToken(String(repeating: "a", count: MCPSettingsStore.maximumTokenBytes)).count
              == MCPSettingsStore.maximumTokenBytes)
        for malformed in ["", "   ", "two words", "line\nbreak", "tab\tinside", "token\r\nX-Injected: 1",
                          "權杖", "caf\u{e9}", String(repeating: "a", count: MCPSettingsStore.maximumTokenBytes + 1)] {
            do {
                _ = try MCPSettingsStore.validateToken(malformed)
                preconditionFailure("A malformed access token was accepted")
            } catch MCPSettingsError.invalidToken { count += 1 }
        }
        print("PASS: \(count) App MCP network/namespace isolation and token checks")
    }
}
