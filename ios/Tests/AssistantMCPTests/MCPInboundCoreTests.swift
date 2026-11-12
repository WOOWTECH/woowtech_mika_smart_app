import XCTest
import Foundation
import AssistantMCP

/// Offline synthetic checks compiled into the actual iOS XCTest bundle.
/// These do not start a listener, use a model, or contact a service.
final class MCPInboundCoreTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var time: UInt64 = 1_000
        func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return time }
        func set(_ value: UInt64) { lock.lock(); time = value; lock.unlock() }
    }
    private let token = String(repeating: "x", count: 43)
    private var peer: MCPInboundPeer { MCPInboundPeer(addressBytes: [127, 0, 0, 1])! }
    private var headers: [MCPInboundHeader] { [.init("Authorization", "Bearer " + token)] }

    private func parse(_ name: String, _ arguments: [String: Any]) throws -> MCPInboundRequest {
        let params: [String: Any] = ["name": name, "arguments": arguments]
        let root: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params]
        return try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: root))
    }
    private func task(_ goal: String) throws -> MCPInboundModelTask {
        guard case .runTask(_, let task) = try parse("mika_run_task", ["goal": goal]) else {
            throw FixtureError.unexpectedRequest
        }
        return task
    }
    private enum FixtureError: Error { case unexpectedRequest, unexpectedStage }
    private func setup(_ clock: Clock) async throws -> (MCPInboundAccessTasks, UUID, MCPInboundReviewBinding) {
        let actor = MCPInboundAccessTasks(clock: { clock.read() }, wallClock: { 1_700_000_000_123 })
        await actor.setForegroundActive(true)
        try await actor.enableByUser(scope: .loopback, token: Data(token.utf8))
        let connection = try await actor.open(peer: peer, headers: headers)
        let binding = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID())
        return (actor, connection, binding)
    }
    private func stage(_ actor: MCPInboundAccessTasks, _ goal: String, _ binding: MCPInboundReviewBinding) async throws -> MCPInboundReview {
        guard case .review(let review) = try await actor.stage(task: task(goal), binding: binding, peer: peer, headers: headers) else {
            throw FixtureError.unexpectedStage
        }
        return review
    }
    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAndroidToolSchemasAndOriginalAnswerSteerArguments() throws {
        let root = try object(MCPInboundResponses.tools(id: .number(1)))
        let result = try XCTUnwrap(root["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let expected: [String: (Set<String>, Set<String>)] = [
            "mika_run_task": (["goal", "request_id", "conversation"], ["goal"]),
            "mika_task_status": (["task_id"], ["task_id"]),
            "mika_wait_task": (["task_id", "timeout_s"], ["task_id"]),
            "mika_answer": (["task_id", "text"], ["task_id", "text"]),
            "mika_steer_task": (["task_id", "text"], ["task_id", "text"]),
            "mika_cancel_task": (["task_id"], ["task_id"]),
            "mika_list_tasks": (["limit"], [])
        ]
        XCTAssertEqual(tools.count, expected.count)
        var seen: Set<String> = []
        for tool in tools {
            let name = try XCTUnwrap(tool["name"] as? String)
            let pair = try XCTUnwrap(expected[name])
            XCTAssertTrue(seen.insert(name).inserted)
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertEqual(Set(properties.keys), pair.0, name)
            XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), pair.1, name)
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false, name)
        }
        XCTAssertEqual(seen, Set(expected.keys))
        XCTAssertEqual(try parse("mika_answer", ["task_id": "t1", "text": " yes "]), .answerTask(.number(1), "t1", nil, nil, "yes"))
        XCTAssertEqual(try parse("mika_steer_task", ["task_id": "t1", "text": " more "]), .steerTask(.number(1), "t1", nil, "more"))
        XCTAssertEqual(try parse("mika_wait_task", ["task_id": "t1"]), .waitTask(.number(1), "t1", 30))
        guard case .runTask(_, let task) = try parse("mika_run_task", ["goal": "work"]) else { return XCTFail("run format") }
        XCTAssertNil(task.requestID)
        XCTAssertThrowsError(try parse("mika_answer", ["task_id": "t1"]))
    }

    func testMaximumListResponsePreservesAllItemsAndBothRepresentations() async throws {
        let clock = Clock()
        let (actor, connection, binding) = try await setup(clock)
        // Legal UTF-16 input with worst-case JSON control-character escaping.
        let goal = "a" + String(repeating: "\u{01}", count: 3_998) + "b"
        for _ in 0..<50 {
            let review = try await stage(actor, goal, binding)
            _ = try await actor.approveLocally(reviewID: review.id, current: binding)
        }
        let snapshots = try await actor.snapshots(limit: 50, connection: connection, peer: peer, headers: headers)
        XCTAssertEqual(snapshots.count, 50)
        let bytes = try MCPInboundResponses.success(id: .number(1), payload: MCPInboundResponses.list(snapshots))
        XCTAssertGreaterThan(bytes.count, 256 * 1024)
        XCTAssertLessThanOrEqual(bytes.count, MCPInboundResponses.maximumResponseBytes)
        let root = try object(bytes)
        let result = try XCTUnwrap(root["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let structured = try XCTUnwrap(result["structuredContent"] as? NSDictionary)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
        XCTAssertEqual(structured, decoded)
        let rows = try XCTUnwrap(structured["tasks"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 50)
        XCTAssertTrue(rows.allSatisfy { $0["goal"] as? String == goal })
        let oversized = JSONValue.object(["x": .string(String(repeating: "x", count: MCPInboundResponses.maximumPayloadBytes + 1))])
        XCTAssertThrowsError(try MCPInboundResponses.success(id: .number(1), payload: oversized))
    }

    func testParseErrorWithoutIDMatchesAndroidAndCanEncodeJSONRPCNull() throws {
        let omitted = try object(MCPInboundResponses.protocolError(id: nil, code: -32700, message: "Parse error"))
        XCTAssertNil(omitted["id"])
        XCTAssertEqual((omitted["error"] as? [String: Any])?["code"] as? Int, -32700)
        let null = try object(MCPInboundResponses.protocolError(id: nil, code: -32700, message: "Parse error", missingID: .null))
        XCTAssertTrue(null["id"] is NSNull)
        let identified = try object(MCPInboundResponses.protocolError(id: .string("request"), code: -32602, message: "Invalid params"))
        XCTAssertEqual(identified["id"] as? String, "request")
    }

    func testExpiredConnectionFreesCapacityAndPendingReview() async throws {
        let clock = Clock()
        let (actor, old, binding) = try await setup(clock)
        let oldReview = try await stage(actor, "old review", binding)
        for _ in 0..<31 { _ = try await actor.open(peer: peer, headers: headers) }
        clock.set(301_000)
        let fresh = try await actor.open(peer: peer, headers: headers)
        let nextBinding = MCPInboundReviewBinding(connection: fresh, destinationRevision: UUID(), contextRevision: UUID())
        let nextReview = try await stage(actor, "new review", nextBinding)
        do {
            try await actor.check(connection: old, peer: peer, headers: headers)
            XCTFail("expired connection survived")
        } catch { XCTAssertEqual(error as? MCPInboundAccessError, .invalidConnection) }
        let discarded = await actor.discardReview(reviewID: oldReview.id)
        XCTAssertFalse(discarded)
        do {
            _ = try await actor.approveLocally(reviewID: oldReview.id, current: binding)
            XCTFail("expired review approved")
        } catch { XCTAssertEqual(error as? MCPInboundAccessError, .invalidReview) }
        let approved = try await actor.approveLocally(reviewID: nextReview.id, current: nextBinding)
        XCTAssertEqual(approved.phase, .queued)
    }

    func testStaleDiscardAndApprovalPreserveReplacementReview() async throws {
        let clock = Clock()
        let (actor, _, binding) = try await setup(clock)
        let old = try await stage(actor, "first", binding)
        let firstDiscard = await actor.discardReview(reviewID: old.id)
        XCTAssertTrue(firstDiscard)
        let next = try await stage(actor, "second", binding)
        let staleDiscard = await actor.discardReview(reviewID: old.id)
        XCTAssertFalse(staleDiscard)
        do {
            _ = try await actor.approveLocally(reviewID: old.id, current: binding)
            XCTFail("stale review approved")
        } catch { XCTAssertEqual(error as? MCPInboundAccessError, .invalidReview) }
        let approved = try await actor.approveLocally(reviewID: next.id, current: binding)
        XCTAssertEqual(approved.phase, .queued)
        let lateDiscard = await actor.discardReview(reviewID: next.id)
        XCTAssertFalse(lateDiscard)
    }
}
