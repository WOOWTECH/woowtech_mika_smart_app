#if DEBUG
import AssistantMCP
import Combine
import Foundation

/// DEBUG-only control for the in-process executor, never for the lease itself.
/// The ordinary chat wrapper must acquire its real encrypted-store lease before
/// the fixture can enter this gate. Release/cancellation only resumes the server.
@MainActor final class UITestMCPLeaseControl: ObservableObject {
    static let shared = UITestMCPLeaseControl()
    @Published private(set) var isHolding = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var holdID: UUID?

    nonisolated static func enabled(arguments: [String]) -> Bool {
        guard arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestMCPFixture" }).count == 1,
              arguments.filter({ $0 == "-UITestMCPLeaseHold" }).count == 1,
              arguments.filter({ $0 == "-UITestNamespace" }).count == 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              let index = arguments.firstIndex(of: "-UITestNamespace"), arguments.indices.contains(index + 1),
              UUID(uuidString: arguments[index + 1]) != nil else { return false }
        return true
    }

    func wait() async throws {
        guard !isHolding else { throw MCPError.busy }
        let id = UUID()
        holdID = id
        isHolding = true
        defer { timeout?.cancel(); timeout = nil; continuation = nil; holdID = nil; isHolding = false }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                continuation = pending
                timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                    self?.release(expected: id)
                }
            }
        } onCancel: {
            Task { @MainActor in UITestMCPLeaseControl.shared.release(expected: id) }
        }
        try Task.checkCancellation()
    }

    func release(expected: UUID? = nil) {
        guard expected == nil || expected == holdID else { return }
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

/// Deterministic in-process servers (MCPFixtureServer). No URLSession or
/// production endpoint is used. Server A offers fixture_echo and a resource;
/// server B offers a tool with the same name, so the chat must tell them apart;
/// the down server never completes its handshake.
actor UITestMCPFixture: MCPDiscovering {
    private var count = 0
    private let holdLease: Bool
    private let server: MCPFixtureServer
    init(endpoint: URL = MCPFixtureServer.a.endpoint, arguments: [String] = ProcessInfo.processInfo.arguments) {
        holdLease = UITestMCPLeaseControl.enabled(arguments: arguments)
        server = MCPFixtureServer(endpoint: endpoint) ?? .down
    }
    /// The model-facing name of a fixture tool (MCPCombinedCatalog, Android's naming).
    nonisolated static func modelName(_ tool: String, on server: MCPFixtureServer = .a) -> String {
        MCPToolNaming.names(server: server.record.key, tools: [tool])[0]
    }
    func initialize() async throws -> MCPServerInfo {
        guard server != .down else { throw MCPError.transportFailure }
        return MCPServerInfo(protocolVersion: "2025-03-26", capabilities: server == .a ? ["tools", "resources"] : ["tools"])
    }
    func listTools() async throws -> [MCPTool] {
        [MCPTool(name: "fixture_echo", description: server == .b ? "Echo text on the second fixture server." : nil,
                 inputSchema: .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]), "additionalProperties": .bool(false)
        ]))]
    }
    func listResources() async throws -> [MCPResource] {
        server == .a ? [MCPResource(uri: "fixture://guide", name: "Fixture guide", mimeType: "text/plain")] : []
    }
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        guard name == "fixture_echo", let text = arguments["text"]?.stringValue else { throw MCPError.invalidRequest }
        if holdLease {
            try await UITestMCPLeaseControl.shared.wait()
        }
        count += 1
        let label = server == .b ? "FIXTURE_B_CALL_" : "FIXTURE_CALL_"
        return .object([
            "isError": .bool(text == "error"),
            "content": .array([.object(["type": .string("text"),
                "text": .string("\(label)\(count): \(text)")])])
        ])
    }
    func readResource(uri: String) async throws -> JSONValue {
        guard server == .a, uri == "fixture://guide" else { throw MCPError.invalidRequest }
        try Task.checkCancellation()
        return .object(["contents": .array([.object([
            "uri": .string(uri), "mimeType": .string("text/plain"), "text": .string("FIXTURE_RESOURCE_OK")
        ])])])
    }
    func cancel() async {}
}
#endif
