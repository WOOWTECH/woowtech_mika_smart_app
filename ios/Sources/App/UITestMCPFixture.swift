#if DEBUG
import AssistantMCP
import Combine
import Foundation

/// Explicitly isolated test mode. Invalid opt-ins fail closed before any client is built.
struct UITestMCPRecoveryConfiguration {
    static let flag = "-UITestMCPRecovery"
    enum Invalid: Error { case arguments }
    static func resolve(arguments: [String]) throws -> Bool {
        guard arguments.contains(where: { $0.hasPrefix(flag) }) else { return false }
        let allowed = [flag, "-UITestMode", "-UITestNamespace", "-UITestResetStorage", "-UITestMCPFixture"]
        guard arguments.filter({ $0 == flag }).count == 1,
              arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestMCPFixture" }).count == 1,
              arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
              arguments.filter({ $0 == "-UITestResetStorage" }).count <= 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              !arguments.contains(where: { $0.hasPrefix("-UITest") && !allowed.contains($0) }),
              let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
              let namespace = UUID(uuidString: arguments[index + 1]),
              namespace.uuidString.lowercased() == arguments[index + 1].lowercased() else { throw Invalid.arguments }
        return true
    }
}

/// Only fixed synthetic counts are observable; no tool arguments or account data.
@MainActor final class UITestMCPRecoveryObservation: ObservableObject {
    static let shared = UITestMCPRecoveryObservation()
    @Published private(set) var entries = 0
    func entered() { entries += 1 }
}

/// Deterministic in-process server. No URLSession or production endpoint is used.
actor UITestMCPFixture: MCPDiscovering {
    private var count = 0
    private let delayRecovery: Bool
    private let sleep: @Sendable (UInt64) async throws -> Void
    init(delayRecovery: Bool = false,
         sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.delayRecovery = delayRecovery
        self.sleep = sleep
    }
    func initialize() async throws -> MCPServerInfo {
        MCPServerInfo(protocolVersion: "2025-03-26", capabilities: ["tools", "resources"])
    }
    func listTools() async throws -> [MCPTool] {
        [MCPTool(name: "fixture_echo", inputSchema: .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]), "additionalProperties": .bool(false)
        ]))]
    }
    func listResources() async throws -> [MCPResource] {
        [MCPResource(uri: "fixture://guide", name: "Fixture guide", mimeType: "text/plain")]
    }
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        guard name == "fixture_echo", let text = arguments["text"]?.stringValue else { throw MCPError.invalidRequest }
        count += 1
        if delayRecovery {
            await UITestMCPRecoveryObservation.shared.entered()
            try await sleep(60_000_000_000)
            try Task.checkCancellation()
        }
        return .object([
            "isError": .bool(text == "error"),
            "content": .array([.object(["type": .string("text"),
                "text": .string("FIXTURE_CALL_\(count): \(text)")])])
        ])
    }
    func readResource(uri: String) async throws -> JSONValue {
        guard uri == "fixture://guide" else { throw MCPError.invalidRequest }
        try Task.checkCancellation()
        return .object(["contents": .array([.object([
            "uri": .string(uri), "mimeType": .string("text/plain"), "text": .string("FIXTURE_RESOURCE_OK")
        ])])])
    }
    func cancel() async {}
}
#endif
