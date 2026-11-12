import Foundation

@main enum ResponseReviewRegressionChecks {
    struct Failure: Error { let label: String }
    static var count = 0
    static let token = String(repeating: "z", count: 43)
    static let headers = [MCPInboundHeader("Authorization", "Bearer " + token)]
    static let peer = MCPInboundPeer(addressBytes: [127,0,0,1])!
    static func check(_ condition: Bool, _ label: String) throws {
        guard condition else { throw Failure(label: label) }; count += 1
    }
    static func task(_ goal: String) throws -> MCPInboundModelTask {
        let params: [String: Any] = ["name": "mika_run_task", "arguments": ["goal": goal]]
        let root: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params]
        guard case .runTask(_, let result) = try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: root)) else { throw Failure(label: "parse task") }
        return result
    }
    static func setup() async throws -> (MCPInboundAccessTasks, UUID, MCPInboundReviewBinding) {
        let core = MCPInboundAccessTasks(clock: { 1000 }, wallClock: { 1700000000123 })
        await core.setForegroundActive(true)
        try await core.enableByUser(scope: .loopback, token: Data(token.utf8))
        let connection = try await core.open(peer: peer, headers: headers)
        return (core, connection, MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID()))
    }
    static func stage(_ core: MCPInboundAccessTasks, _ goal: String, _ binding: MCPInboundReviewBinding) async throws -> MCPInboundReview {
        guard case .review(let review) = try await core.stage(task: try task(goal), binding: binding, peer: peer, headers: headers) else { throw Failure(label: "stage") }
        return review
    }
    static func listBoundaries() async throws {
        // The control-character case expands to six bytes in structuredContent
        // and seven in its JSON-string copy, beyond the original 256 KiB cap.
        let goals = [String(repeating:"x", count:4000),
                     "a" + String(repeating:"\u{01}", count:3998) + "b",
                     String(repeating:"\\", count:4000),
                     String(repeating:"😀", count:2000)]
        for goal in goals {
            let (core, connection, binding) = try await setup()
            for _ in 0..<50 {
                let review = try await stage(core, goal, binding)
                _ = try await core.approveLocally(reviewID: review.id, current: binding)
            }
            let snapshots = try await core.snapshots(limit: 50, connection: connection, peer: peer, headers: headers)
            try check(snapshots.count == 50, "all 50 tasks retained")
            let payload = MCPInboundResponses.list(snapshots)
            let encoded = try MCPInboundResponses.success(id: .number(1), payload: payload)
            try check(encoded.count > 256 * 1024 && encoded.count <= MCPInboundResponses.maximumResponseBytes, "full valid envelope fits")
            let root = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            let result = root["result"] as! [String: Any]
            let structured = result["structuredContent"] as! NSDictionary
            let text = ((result["content"] as! [[String: Any]])[0]["text"] as! String)
            let embedded = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! NSDictionary
            try check(structured == embedded, "text and structuredContent match")
            let rows = structured["tasks"] as! [[String: Any]]
            try check(rows.count == 50 && rows.allSatisfy { $0["goal"] as? String == goal }, "every full goal survives JSON")
        }
        do {
            _ = try MCPInboundResponses.success(id: .number(1), payload: .object(["x": .string(String(repeating: "a", count: MCPInboundResponses.maximumPayloadBytes + 1))]))
            throw Failure(label: "unbounded payload")
        } catch MCPInboundResponses.Error.tooLarge { count += 1 }
        do {
            _ = try MCPInboundResponses.success(id: .number(1), payload: .object(["x": .string(String(repeating: "\\", count: 800_000))]))
            throw Failure(label: "unbounded doubled envelope")
        } catch MCPInboundResponses.Error.tooLarge { count += 1 }
    }
    static func errors() throws {
        func decode(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        let noID = try decode(MCPInboundResponses.protocolError(id: nil, code: -32700, message: "Parse error"))
        try check(noID["id"] == nil && (noID["error"] as? [String: Any])?["code"] as? Int == -32700, "Android missing id")
        let nullID = try decode(MCPInboundResponses.protocolError(id: nil, code: -32700, message: "Parse error", missingID: .null))
        try check(nullID["id"] is NSNull, "explicit JSON-RPC null id")
        let stringID = try decode(MCPInboundResponses.protocolError(id: .string("a"), code: -32602, message: "Invalid params"))
        try check(stringID["id"] as? String == "a", "string id retained")
        let numberID = try decode(MCPInboundResponses.protocolError(id: .number(42), code: -32600, message: "Invalid request"))
        try check(numberID["id"] as? Int == 42, "numeric id retained")
    }
    static func staleDiscard() async throws {
        let (core, _, binding) = try await setup()
        let old = try await stage(core, "first", binding)
        try check(await core.discardReview(reviewID: old.id), "discard current")
        let fresh = try await stage(core, "second", binding)
        try check(!(await core.discardReview(reviewID: old.id)), "stale discard rejected")
        let approved = try await core.approveLocally(reviewID: fresh.id, current: binding)
        try check(approved.phase == .queued, "new review preserved")
        try check(!(await core.discardReview(reviewID: fresh.id)), "discard cannot undo approval")
        let state = MCPInboundReviewState()
        await state.setEnabledByUser(true); await state.setForegroundActive(true)
        guard let first = await state.stage(try task("old"), binding: binding),
              let oldGrant = await state.approveLocally(ticket: first.id, current: binding),
              let next = await state.stage(try task("new"), binding: binding) else { throw Failure(label: "review state setup") }
        try check(!(await state.discard(grant: oldGrant)), "stale grant cannot discard pending")
        try check(!(await state.discard(ticket: first.id)), "stale ticket cannot discard pending")
        guard let newGrant = await state.approveLocally(ticket: next.id, current: binding) else { throw Failure(label: "new approval") }
        try check(!(await state.discard(grant: oldGrant)), "stale grant cannot discard newer grant")
        try check(await state.consume(grant: newGrant, current: binding)?.goal == "new", "new grant preserved")
    }
    static func main() async {
        do { try errors(); try await staleDiscard(); try await listBoundaries(); print("PASS response review regressions: \(count) checks; synthetic only") }
        catch { print("FAIL response review regressions: \(error)"); exit(1) }
    }
}
