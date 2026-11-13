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

/// Deterministic in-process server. No URLSession or production endpoint is used.
actor UITestMCPFixture: MCPDiscovering {
    private var count = 0
    private let holdLease: Bool
    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        holdLease = UITestMCPLeaseControl.enabled(arguments: arguments)
    }
    func initialize() async throws -> MCPServerInfo {
        MCPServerInfo(protocolVersion: "2025-03-26", capabilities: ["tools"])
    }
    func listTools() async throws -> [MCPTool] {
        [MCPTool(name: "fixture_echo", inputSchema: .object([
            "type": .string("object"), "properties": .object(["text": .object(["type": .string("string")])]),
            "required": .array([.string("text")]), "additionalProperties": .bool(false)
        ]))]
    }
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        guard name == "fixture_echo", let text = arguments["text"]?.stringValue else { throw MCPError.invalidRequest }
        if holdLease {
            try await UITestMCPLeaseControl.shared.wait()
        }
        count += 1
        return .object([
            "isError": .bool(text == "error"),
            "content": .array([.object(["type": .string("text"),
                "text": .string("FIXTURE_CALL_\(count): \(text)")])])
        ])
    }
    func readResource(uri: String) async throws -> JSONValue { throw MCPError.invalidRequest }
    func cancel() async {}
}
#endif
