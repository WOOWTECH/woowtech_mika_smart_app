import Foundation

@main enum InboundChecks {
    static var count = 0
    static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw Failure(name: name) }; count += 1
    }
    struct Failure: Error { let name: String }
    static func parse(_ body: String) throws -> MCPInboundRequest { try MCPInboundFormat.parse(Data(body.utf8)) }
    static func rejects(_ body: String, _ error: MCPInboundFormatError) throws {
        do { _ = try parse(body); throw Failure(name: "unexpected acceptance") }
        catch let actual as MCPInboundFormatError { try check(actual == error, "wrong rejection") }
    }
    static func task(_ goal: String = "hello", id: String = "") throws -> MCPInboundModelTask {
        let params: [String: Any] = ["name":"mika_run_task", "arguments":["goal":goal].merging(id.isEmpty ? [:] : ["request_id":id]) { _, b in b }]
        let root: [String: Any] = ["jsonrpc":"2.0", "id":1, "method":"tools/call", "params":params]
        let data = try JSONSerialization.data(withJSONObject: root)
        guard case .runTask(_, let task) = try MCPInboundFormat.parse(data) else { throw Failure(name: "missing task") }
        return task
    }
    static func main() async {
        do {
            let initialization = #"{"jsonrpc":"2.0","id":42,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"synthetic","version":"1"}}}"#
            try check(try parse(initialization) == .initialize(.number(42), "2025-06-18"), "legacy initialize")
            try check(try parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == .initialized, "notification")
            try check(try parse(#"{"jsonrpc":"2.0","id":"p","method":"ping"}"#) == .ping(.string("p")), "ping")
            try check(try parse(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#) == .listTools(.number(2)), "tools list")
            let requestID = "01234567-89ab-cdef-0123-456789abcdef"
            let run = #"{"jsonrpc":"2.0","id":"x","method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"  hello ","request_id":"01234567-89ab-cdef-0123-456789abcdef","conversation":"mcp-01234567-89ab-cdef-0123-456789abcdef"}}}"#
            guard case .runTask(.string("x"), let parsed) = try parse(run) else { throw Failure(name: "run") }
            try check(parsed.goal == "hello" && parsed.requestID?.uuidString.lowercased() == requestID && parsed.conversation == "mcp-" + requestID, "typed task")
            try check(try task(String(repeating: "😀", count: 2000)).goal.utf16.count == 4000, "Android UTF16 boundary")
            do { _ = try task(String(repeating: "😀", count: 2001)); throw Failure(name: "oversize goal") } catch MCPInboundFormatError.invalidParameters { count += 1 }
            for body in [#"{}"#, #"[]"#, #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#,
                         #"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, #"{"jsonrpc":"2.0","method":"ping"}"#] {
                try rejects(body, .invalidRequest)
            }
            for body in [#"{"jsonrpc":"2.0","id":1,"method":"ping","method":"tools/list"}"#,
                         #"{"jsonrpc":"2.0","id":1,"method":"ping","\u006dethod":"tools/list"}"#,
                         #"{"jsonrpc":"2.0","id":1,"method":"ping"}junk"#,
                         #"{"jsonrpc":"2.0","id":1,"method":"ping",}"#] { try rejects(body, .malformed) }
            do { _ = try MCPInboundFormat.parse(Data([0xff])); throw Failure(name: "invalid UTF8") } catch MCPInboundFormatError.malformed { count += 1 }
            do { _ = try MCPInboundFormat.parse(Data(repeating: 32, count: MCPInboundFormat.maximumBytes + 1)); throw Failure(name: "size") } catch MCPInboundFormatError.tooLarge { count += 1 }
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2026-07-28","capabilities":{},"clientInfo":{}}}"#, .unsupportedVersion)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"device_tap","arguments":{}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"x","request_id":null}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"x","conversation":"mcp-FAKE"}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"x","device":"tap"}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"  "}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"x","request_id":"01234567-89AB-CDEF-0123-456789ABCDEF"}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"server/discover"}"#, .unsupportedMethod)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"a","\u0067oal":"b"}}}"#, .malformed)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"ping","params":{"_meta":{}}}"#, .invalidParameters)
            try rejects(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_run_task","arguments":{"goal":"x","request_id":5}}}"#, .invalidParameters)
            let nested = String(repeating: "[", count: 18) + "0" + String(repeating: "]", count: 18)
            try rejects(nested, .malformed)
            let many = "[" + Array(repeating: "0", count: 513).joined(separator: ",") + "]"
            try rejects(many, .malformed)

            let state = MCPInboundReviewState()
            let binding = MCPInboundReviewBinding(connection: UUID(), destinationRevision: UUID(), contextRevision: UUID())
            let changed = MCPInboundReviewBinding(connection: binding.connection, destinationRevision: UUID(), contextRevision: binding.contextRevision)
            let t = try task()
            try check(await state.stage(t, binding: binding) == nil, "default closed")
            await state.setEnabledByUser(true)
            try check(await state.stage(t, binding: binding) == nil, "inactive closed")
            await state.setForegroundActive(true)
            guard let first = await state.stage(t, binding: binding) else { throw Failure(name: "stage") }
            try check(first.task == t && first.binding == binding, "review snapshot displays the exact task and binding")
            try check(await state.approveLocally(ticket: first.id, current: changed) == nil, "destination changed")
            try check(await state.approveLocally(ticket: first.id, current: binding) == nil, "changed review cannot revive")
            guard let second = await state.stage(t, binding: binding), let grant = await state.approveLocally(ticket: second.id, current: binding) else { throw Failure(name: "approval") }
            try check(await state.consume(grant: grant, current: changed) == nil, "changed destination blocks consumption")
            try check(await state.consume(grant: grant, current: binding) == nil, "failed grant cannot revive")
            guard let third = await state.stage(t, binding: binding), let g = await state.approveLocally(ticket: third.id, current: binding) else { throw Failure(name: "approval 2") }
            let one = await state.consume(grant: g, current: binding)
            let two = await state.consume(grant: g, current: binding)
            try check(one == t && two == nil, "grant is single use")
            guard let fourth = await state.stage(t, binding: binding), let g2 = await state.approveLocally(ticket: fourth.id, current: binding) else { throw Failure(name: "approval 3") }
            await state.setForegroundActive(false); await state.setForegroundActive(true)
            try check(await state.consume(grant: g2, current: binding) == nil, "inactive invalidates")
            guard let fifth = await state.stage(t, binding: binding) else { throw Failure(name: "stage 5") }
            await state.setEnabledByUser(false); await state.setEnabledByUser(true)
            try check(await state.approveLocally(ticket: fifth.id, current: binding) == nil, "disable invalidates")
            guard let old = await state.stage(t, binding: binding), let replacement = await state.stage(try task("new"), binding: binding) else { throw Failure(name: "replace") }
            try check(await state.approveLocally(ticket: old.id, current: binding) == nil, "old ticket rejected")
            try check(await state.approveLocally(ticket: replacement.id, current: binding) != nil, "stale attempt preserves replacement")
            guard let stale = await state.stage(t, binding: binding), let staleGrant = await state.approveLocally(ticket: stale.id, current: binding),
                  let currentTicket = await state.stage(t, binding: binding), let currentGrant = await state.approveLocally(ticket: currentTicket.id, current: binding) else { throw Failure(name: "grant replacement") }
            try check(await state.consume(grant: staleGrant, current: binding) == nil, "stale grant rejected")
            try check(await state.consume(grant: currentGrant, current: binding) == t, "stale grant preserves current")
            guard let race = await state.stage(t, binding: binding), let raceGrant = await state.approveLocally(ticket: race.id, current: binding) else { throw Failure(name: "race setup") }
            let results = await withTaskGroup(of: MCPInboundModelTask?.self, returning: [MCPInboundModelTask?].self) { group in
                for _ in 0..<8 { group.addTask { await state.consume(grant: raceGrant, current: binding) } }
                var collected: [MCPInboundModelTask?] = []
                for await result in group { collected.append(result) }
                return collected
            }
            try check(results.compactMap { $0 }.count == 1, "concurrent consumers: exactly one grant")
            guard let discarded = await state.stage(t, binding: binding) else { throw Failure(name: "discard setup") }
            await state.discard(ticket: discarded.id)
            try check(await state.approveLocally(ticket: discarded.id, current: binding) == nil, "discard invalidates")
            let newConnection = MCPInboundReviewBinding(connection: UUID(), destinationRevision: binding.destinationRevision, contextRevision: binding.contextRevision)
            guard let connectionTicket = await state.stage(t, binding: binding) else { throw Failure(name: "connection setup") }
            try check(await state.approveLocally(ticket: connectionTicket.id, current: newConnection) == nil, "connection switch invalidates")
            let newContext = MCPInboundReviewBinding(connection: binding.connection, destinationRevision: binding.destinationRevision, contextRevision: UUID())
            guard let contextTicket = await state.stage(t, binding: binding), let contextGrant = await state.approveLocally(ticket: contextTicket.id, current: binding) else { throw Failure(name: "context setup") }
            try check(await state.consume(grant: contextGrant, current: newContext) == nil, "context switch invalidates")
            print("PASS inbound: \(count) checks; no network, storage, UI, or model")
        } catch { print("FAIL inbound: \(error)"); exit(1) }
    }
}
