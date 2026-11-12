import Foundation

/// Offline legacy tools/call response formatting only. The caller must obtain
/// snapshots through the authenticated actor; this codec performs no access check.
public enum MCPInboundResponses {
    public enum Error: Swift.Error { case tooLarge }
    /// A list has at most 50 goals of 4,000 UTF-16 units. JSON can encode
    /// one control unit as six bytes and the text copy escapes it again.
    public static let maximumPayloadBytes = 2 * 1024 * 1024
    public static let maximumResponseBytes = 4 * 1024 * 1024
    public enum MissingErrorID: Sendable { case omitted, null }
    private static func id(_ id: MCPInboundID) -> JSONValue {
        switch id { case .string(let value): return .string(value); case .number(let value): return .number(value) }
    }
    private static func uuid(_ value: UUID) -> JSONValue { .string(value.uuidString.lowercased()) }
    private static func data(_ value: JSONValue, limit: Int = maximumResponseBytes) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let result = try encoder.encode(value)
        guard result.count <= limit else { throw Error.tooLarge }
        return result
    }
    private static func result(id requestID: MCPInboundID, value: JSONValue) throws -> Data {
        try data(.object(["jsonrpc": .string("2.0"), "id": id(requestID), "result": value]))
    }
    public static func initialize(id: MCPInboundID, version: String, serverVersion: String) throws -> Data {
        guard MCPInboundFormat.legacyVersions.contains(version), !serverVersion.isEmpty,
              serverVersion.utf8.count <= 128 else { throw MCPError.invalidResponse }
        return try result(id: id, value: .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": .object(["name": .string("mika"), "title": .string("渥屋助理"), "version": .string(serverVersion)]),
            "instructions": .string("Submit model tasks for local review; protected actions require local approval.")
        ]))
    }
    public static func ping(id: MCPInboundID) throws -> Data { try result(id: id, value: .object([:])) }
    /// Legacy tools/list schemas follow Android's original required and optional
    /// fields. iOS-only input extensions are deliberately not advertised.
    public static func tools(id: MCPInboundID) throws -> Data {
        func string(_ format: String? = nil, max: Int? = nil) -> JSONValue {
            var p: [String: JSONValue] = ["type": .string("string")]
            if let format { p["format"] = .string(format) }
            if let max { p["minLength"] = .number(1); p["maxLength"] = .number(Decimal(max)) }
            return .object(p)
        }
        func integer(max: Int) -> JSONValue { .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(Decimal(max))]) }
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue], _ required: [String], _ readOnly: Bool) -> JSONValue {
            let schema: JSONValue = .object(["type": .string("object"), "properties": .object(properties),
                "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false)])
            var annotations: [String: JSONValue] = ["readOnlyHint": .bool(readOnly),
                "openWorldHint": .bool(name == "mika_run_task" || name == "mika_steer_task")]
            if !readOnly { annotations["destructiveHint"] = .bool(name != "mika_answer") }
            return .object(["name": .string(name), "description": .string(description), "inputSchema": schema, "annotations": .object(annotations)])
        }
        let tools: [JSONValue] = [
            tool("mika_run_task", "Submit a model task for local review.", ["goal":string(), "request_id":string("uuid"), "conversation":string()], ["goal"], false),
            tool("mika_task_status", "Get task status.", ["task_id":string()], ["task_id"], true),
            tool("mika_wait_task", "Wait for task status to change.", ["task_id":string(), "timeout_s":integer(max:50)], ["task_id"], true),
            tool("mika_answer", "Answer an open question; local approvals cannot be answered remotely.", ["task_id":string(), "text":string()], ["task_id","text"], false),
            tool("mika_steer_task", "Add an instruction to a running task.", ["task_id":string(), "text":string(max:4000)], ["task_id","text"], false),
            tool("mika_cancel_task", "Cancel a task.", ["task_id":string()], ["task_id"], false),
            tool("mika_list_tasks", "List recent tasks.", ["limit":integer(max:50)], [], true)
        ]
        return try result(id: id, value: .object(["tools": .array(tools)]))
    }
    /// Android omits id when parsing fails before it can be read. Callers
    /// requiring strict JSON-RPC null may opt in explicitly.
    public static func protocolError(id requestID: MCPInboundID?, code: Int, message: String,
                                     missingID: MissingErrorID = .omitted) throws -> Data {
        guard [-32600, -32601, -32602, -32700].contains(code), message.utf8.count <= 256 else { throw MCPError.invalidResponse }
        var envelope: [String: JSONValue] = ["jsonrpc": .string("2.0"),
            "error": .object(["code": .number(Decimal(code)), "message": .string(message)])]
        if let requestID { envelope["id"] = id(requestID) }
        else if missingID == .null { envelope["id"] = .null }
        return try data(.object(envelope))
    }
    /// Matches Android's legacy envelope: content text contains JSON for the
    /// exact structuredContent object; failures do not contain structuredContent.
    public static func success(id requestID: MCPInboundID, payload: JSONValue) throws -> Data {
        guard case .object = payload else { throw MCPError.invalidResponse }
        let text = String(decoding: try data(payload, limit: maximumPayloadBytes), as: UTF8.self)
        return try data(.object(["jsonrpc": .string("2.0"), "id": id(requestID), "result": .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": payload, "isError": .bool(false)
        ])]))
    }
    /// Fixed messages only; no untrusted input, credentials or underlying errors.
    public static func failure(id requestID: MCPInboundID, error: MCPInboundAccessError) throws -> Data {
        let message: String
        switch error {
        case .missing: message = "No MCP task with this id"
        case .busy: message = "A local review is already pending."
        case .conflict: message = "The task or conversation is not available in this state."
        case .capacity: message = "The task limit was reached."
        case .unsupported: message = "The request is not supported."
        default: message = "The request could not be completed."
        }
        return try data(.object(["jsonrpc": .string("2.0"), "id": id(requestID), "result": .object([
            "content": .array([.object(["type": .string("text"), "text": .string(message)])]), "isError": .bool(true)
        ])]))
    }
    private static func status(_ phase: MCPInboundTaskPhase) -> String {
        switch phase {
        case .queued: return "starting"
        case .running: return "running"
        case .waitingForAnswer: return "waiting_for_answer"
        case .waitingForLocalApproval: return "waiting_on_phone"
        case .finished: return "done"
        case .cancelled: return "cancelled"
        }
    }
    public static func task(_ snapshot: MCPInboundSnapshot, changed: Bool? = nil) -> JSONValue {
        var result: [String: JSONValue] = [
            "task_id": uuid(snapshot.status.taskID), "status": .string(status(snapshot.status.phase)),
            "conversation": .string(snapshot.conversation), "goal": .string(snapshot.goal),
            "started_at_ms": .number(Decimal(snapshot.startedAtMs)),
            "answerable": .bool(snapshot.status.phase == .waitingForAnswer)
        ]
        if snapshot.status.phase == .running { result["step"] = .number(0) }
        if let question = snapshot.status.question, snapshot.status.phase == .waitingForAnswer {
            result["question"] = .string(question.text)
            result["note"] = .string("Mika is asking a question. Reply with mika_answer; the user can also answer locally.")
        }
        if snapshot.status.phase == .waitingForLocalApproval {
            result["note"] = .string("This step needs local user approval and cannot be answered over MCP.")
        }
        if let answer = snapshot.answer, snapshot.status.phase == .finished { result["answer"] = .string(answer) }
        if !snapshot.steers.isEmpty {
            result["steers"] = .array(snapshot.steers.map { .object(["message_id": uuid($0.id), "state": .string($0.state)]) })
        }
        if let changed { result["changed"] = .bool(changed) }
        return .object(result)
    }
    public static func list(_ snapshots: [MCPInboundSnapshot]) -> JSONValue {
        .object(["tasks": .array(snapshots.map { snapshot in .object([
            "task_id": uuid(snapshot.status.taskID), "status": .string(status(snapshot.status.phase)),
            "goal": .string(snapshot.goal), "conversation": .string(snapshot.conversation),
            "started_at_ms": .number(Decimal(snapshot.startedAtMs))
        ]) })])
    }
    public static func answer(taskID: UUID) -> JSONValue { .object(["task_id": uuid(taskID), "accepted": .bool(true)]) }
    public static func steer(taskID: UUID, messageID: UUID) -> JSONValue {
        .object(["task_id": uuid(taskID), "message_id": uuid(messageID), "accepted": .bool(true)])
    }
    public static func cancel(taskID: UUID, cancelled: Bool, terminal: MCPInboundTaskPhase? = nil) -> JSONValue {
        var result: [String: JSONValue] = ["task_id": uuid(taskID), "cancelled": .bool(cancelled)]
        if let terminal, terminal == .finished || terminal == .cancelled { result["status"] = .string(status(terminal)) }
        return .object(result)
    }
}
