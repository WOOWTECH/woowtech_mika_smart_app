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
        count += try serverDirectory()
        print("PASS: \(count) App MCP network/namespace isolation, token and server list checks")
    }

    /// Several servers in one Keychain service, through the same code as the
    /// Keychain but with items in memory: migration, per-server deletion and
    /// writes that fail. Never the real Keychain.
    static func serverDirectory() throws -> Int {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, "App MCP server list check failed: " + label)
            count += 1
        }
        func text(_ items: MCPMemoryItems, _ account: String) -> String? {
            (try? items.read(account)).flatMap { $0 }.map { String(decoding: $0, as: UTF8.self) }
        }
        // The single-server version kept one server directly in the service.
        let items = MCPMemoryItems()
        let legacy = MCPSettingsStore(items: items)
        try legacy.save(endpoint: "https://legacy.invalid/mcp?key=secret")
        try legacy.save(token: "legacy-token-value")
        try legacy.save(allowedTools: ["read_state"])
        let directory = MCPServerDirectory(items: items)
        let migrated = try directory.load()
        check(migrated.count == 1 && migrated[0].legacy && migrated[0].enabled && migrated[0].name.isEmpty,
              "the single server becomes the first entry")
        check(Set(items.values.keys) == ["endpoint", "token", "allowed-tools", "servers"], "nothing is copied or renamed")
        let first = directory.store(for: migrated[0])
        check(try first.load()?.absoluteString == "https://legacy.invalid/mcp?key=secret" && first.loadToken() == "legacy-token-value"
              && first.loadAllowedTools() == ["read_state"], "endpoint, token and tool choice survive the migration")
        check(try directory.load() == migrated, "the list is saved: the same id next time")
        // A second server gets its own accounts and a key no other server uses.
        let second = try directory.add(name: "  Helpdesk  ", endpoint: "https://helpdesk.invalid/mcp", token: "second-token",
                                       to: migrated)
        let saved = try directory.load()
        check(saved.map(\.id) == [migrated[0].id, second.id] && second.name == "Helpdesk" && !second.legacy
              && second.key != migrated[0].key, "a named second server after the first")
        let prefix = "server." + second.id.uuidString + "."
        check(text(items, prefix + "endpoint") == "https://helpdesk.invalid/mcp" && text(items, prefix + "token") == "second-token",
              "the second server's endpoint and token have their own accounts")
        check(try directory.store(for: second).loadAllowedTools() == nil, "a new server allows every tool")
        // Deleting a server removes only its items.
        let remaining = try directory.remove(migrated[0], from: saved)
        check(try remaining.map(\.id) == [second.id] && directory.load() == remaining, "the entry goes")
        check(Set(items.values.keys) == [prefix + "endpoint", prefix + "token", "servers"],
              "only the first server's endpoint, token and tool choice are deleted")
        check(try directory.store(for: second).loadToken() == "second-token", "the other server keeps its token")
        _ = try directory.remove(second, from: remaining)
        check(try Set(items.values.keys) == ["servers"] && directory.load().isEmpty, "the last server goes; the empty list stays")
        // A failed write leaves nothing of a new server behind.
        let failing = MCPMemoryItems(); failing.failWrites = true
        do {
            _ = try MCPServerDirectory(items: failing).add(name: "A", endpoint: "https://a.invalid/mcp", token: nil, to: [])
            preconditionFailure("a failed write was accepted")
        } catch MCPSettingsError.unavailableKeychain { count += 1 }
        check(failing.values.isEmpty, "no orphaned endpoint after a failed write")
        // Names reach the model in tool descriptions: no endpoint, token, or second line.
        for (name, endpoint, token) in [("", "https://a.invalid/mcp", nil), ("two\nlines", "https://a.invalid/mcp", nil),
                                        (String(repeating: "n", count: 41), "https://a.invalid/mcp", nil),
                                        ("x https://a.invalid/mcp", "https://a.invalid/mcp", nil),
                                        ("uses token-1234567", "https://a.invalid/mcp", "token-1234567")] as [(String, String, String?)] {
            do {
                _ = try MCPServerDirectory.validateName(name, endpoint: endpoint, token: token)
                preconditionFailure("an unsafe server name was accepted")
            } catch MCPSettingsError.invalidName { count += 1 }
        }
        check(try MCPServerDirectory.validateName(" Odoo 銷售 ", endpoint: "https://a.invalid/mcp", token: "token-1234567") == "Odoo 銷售",
              "an ordinary name is trimmed")
        let full = (0..<MCPServerDirectory.maximumServers).map { _ in MCPServerDirectory.newRecord(name: "n", existing: []) }
        do {
            _ = try MCPServerDirectory(items: MCPMemoryItems()).add(name: "n", endpoint: "https://a.invalid/mcp", token: nil, to: full)
            preconditionFailure("a seventeenth server was accepted")
        } catch MCPSettingsError.tooManyServers { count += 1 }
        // A clearing reset (fresh install, UI test reset) removes every server and the list.
        let all = MCPMemoryItems()
        let both = MCPServerDirectory(items: all)
        let a = try both.add(name: "A", endpoint: "https://a.invalid/mcp", token: "token-aaaaaaaa", to: [])
        _ = try both.add(name: "B", endpoint: "https://b.invalid/mcp", token: nil, to: [a])
        try both.removeAll()
        check(try all.values.isEmpty && both.load().isEmpty, "removeAll clears every server and the list")
        // UI-test fixtures (DEBUG): two servers sharing a tool name, one down, and the single-server version.
        let fixtures = MCPServerDirectory(items: MCPMemoryItems())
        try fixtures.seedFixtures(arguments: ["-UITestMCPServers"])
        try fixtures.seedFixtures(arguments: ["-UITestMCPServers"])
        check(try fixtures.load().map(\.name) == ["Fixture A", "Fixture B", "Fixture down"], "fixtures are seeded once")
        let legacyItems = MCPMemoryItems()
        try MCPServerDirectory(items: legacyItems).seedFixtures(arguments: ["-UITestMCPLegacyServer"])
        check(Set(legacyItems.values.keys) == ["endpoint", "token", "allowed-tools"], "the legacy fixture has no list yet")
        let legacyRecords = try MCPServerDirectory(items: legacyItems).load()
        check(try legacyRecords.count == 1 && legacyRecords[0].legacy
              && MCPServerDirectory(items: legacyItems).store(for: legacyRecords[0]).loadAllowedTools() == [],
              "the legacy fixture migrates with its tool choice")
        return count
    }
}
