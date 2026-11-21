#if !MCP_SMOKE
import Foundation
import XCTest
@testable import AssistantMCP

/// URLProtocol fixtures exercise the actual client actor's session state. The
/// separate loopback suite covers actual socket responses, timeouts and closes.
final class MCPClientLifecycleTests: XCTestCase {
    func testCancelledCachedInitializeDoesNotReportSuccess() async throws {
        let scenario = MCPProtocolFixture.Scenario { _, body, _ in
            if let reply = try MCPClientChecks.initialized(body) { return reply }
            return try .result(.object([:]), request: body)
        }
        let endpoint = MCPProtocolFixture.register(scenario)
        defer { MCPProtocolFixture.remove(endpoint) }
        let client = MCPClient(endpoint: endpoint, configuration: MCPProtocolFixture.configuration())
        _ = try await client.initialize()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.initialize()
        }
        _ = try await MCPClientChecks.expectError(.cancelled) { _ = try await cancelled.value }
        XCTAssertEqual(scenario.records.count, 2)
        // Cancelling the caller does not discard an already established session.
        _ = try await client.initialize()
        try await client.ping()
        XCTAssertEqual(scenario.records.count, 3)
    }

    func testSession404RequiresExplicitReinitializeAndNeverReplaysTool() async throws {
        let scenario = MCPProtocolFixture.Scenario { _, body, index in
            if let reply = try MCPClientChecks.initialized(body, session: index <= 3 ? "old-session" : "new-session") {
                return reply
            }
            if body["method"] == .string("tools/call") { return .init(status: 404) }
            return try .result(.object([:]), request: body)
        }
        let endpoint = MCPProtocolFixture.register(scenario)
        defer { MCPProtocolFixture.remove(endpoint) }
        let client = MCPClient(endpoint: endpoint, configuration: MCPProtocolFixture.configuration())
        _ = try await client.initialize()
        _ = try await MCPClientChecks.expectError(.httpStatus(statusCode: 404)) {
            _ = try await client.callAuthorizedTool(name: "fixture_write", arguments: .object([:]))
        }
        _ = try await MCPClientChecks.expectError(.notInitialized) { try await client.ping() }
        XCTAssertEqual(scenario.records.count, 3)
        _ = try await client.initialize()
        try await client.ping()
        let records = scenario.records
        XCTAssertEqual(records.map { $0.1["method"]?.stringValue },
                       ["initialize", "notifications/initialized", "tools/call", "initialize", "notifications/initialized", "ping"])
        XCTAssertNil(records[3].0.value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertEqual(records[5].0.value(forHTTPHeaderField: "Mcp-Session-Id"), "new-session")
    }

    func testCancelledInitializationNotificationClearsProvisionalSession() async throws {
        let scenario = MCPProtocolFixture.Scenario { _, body, index in
            if index == 2 { return .init(holdBeforeHeaders: true) }
            if let reply = try MCPClientChecks.initialized(body, session: index <= 2 ? "partial-session" : "fresh-session") {
                return reply
            }
            return try .result(.object([:]), request: body)
        }
        let endpoint = MCPProtocolFixture.register(scenario)
        defer { MCPProtocolFixture.remove(endpoint) }
        let client = MCPClient(endpoint: endpoint, configuration: MCPProtocolFixture.configuration())
        let worker = Task { try await client.initialize() }
        defer { worker.cancel() }
        for _ in 0..<500 {
            if scenario.records.count == 2 { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(scenario.records.count, 2)
        await client.cancel()
        _ = try await MCPClientChecks.expectError(.cancelled) { _ = try await worker.value }
        _ = try await MCPClientChecks.expectError(.notInitialized) { try await client.ping() }
        _ = try await client.initialize()
        try await client.ping()
        let records = scenario.records
        XCTAssertEqual(records.count, 5)
        XCTAssertNil(records[2].0.value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertEqual(records[4].0.value(forHTTPHeaderField: "Mcp-Session-Id"), "fresh-session")
        XCTAssertFalse(records.contains { $0.1["method"] == .string("tools/call") })
    }
}
#endif
