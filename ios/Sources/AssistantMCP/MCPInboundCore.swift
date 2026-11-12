import Foundation

/// A format-only subset. These values are untrusted data and never authorize work.
public struct MCPInboundModelTask: Sendable, Equatable {
    public let goal: String
    public let requestID: UUID?
    public let conversation: String?
}

public enum MCPInboundID: Sendable, Equatable {
    case string(String)
    case number(Decimal)
}

public enum MCPInboundRequest: Sendable, Equatable {
    case initialize(MCPInboundID, String)
    case initialized
    case ping(MCPInboundID)
    case listTools(MCPInboundID)
    case runTask(MCPInboundID, MCPInboundModelTask)
    case taskStatus(MCPInboundID, UUID)
    case cancelTask(MCPInboundID, UUID)
    case listTasks(MCPInboundID, Int)
    case waitTask(MCPInboundID, UUID, Int)
    case answerTask(MCPInboundID, UUID, UUID, UUID, String)
    case steerTask(MCPInboundID, UUID, UUID, String)
}

public enum MCPInboundFormatError: Error, Sendable, Equatable {
    case tooLarge, malformed, invalidRequest, unsupportedMethod, invalidParameters, unsupportedVersion
}

/// Parses only legacy JSON-RPC request bodies. This is not an HTTP endpoint,
/// authenticator, MCP server, response encoder, or model dispatcher.
public enum MCPInboundFormat {
    public static let maximumBytes = 32 * 1024
    public static let legacyVersions: Set<String> = ["2025-03-26", "2025-06-18", "2025-11-25"]

    public static func parse(_ bytes: Data) throws -> MCPInboundRequest {
        guard bytes.count <= maximumBytes else { throw MCPInboundFormatError.tooLarge }
        var parser = StrictJSON(bytes: Array(bytes))
        guard case .object(let root) = try parser.parse(), root["jsonrpc"] == .string("2.0"),
              let method = root["method"]?.stringValue,
              Set(root.keys).isSubset(of: ["jsonrpc", "id", "method", "params"]) else {
            throw MCPInboundFormatError.invalidRequest
        }
        let params: [String: JSONValue]
        switch root["params"] {
        case nil, .null?: params = [:]
        case .object(let object)?: params = object
        default: throw MCPInboundFormatError.invalidParameters
        }
        if method == "notifications/initialized" {
            guard root["id"] == nil, params.isEmpty else { throw MCPInboundFormatError.invalidRequest }
            return .initialized
        }
        let id: MCPInboundID
        switch root["id"] {
        case .string(let value)? where !value.isEmpty && value.utf8.count <= 128: id = .string(value)
        case .number(let value)? where !value.isNaN: id = .number(value)
        default: throw MCPInboundFormatError.invalidRequest
        }
        switch method {
        case "initialize":
            guard let version = params["protocolVersion"]?.stringValue else { throw MCPInboundFormatError.invalidParameters }
            guard legacyVersions.contains(version) else { throw MCPInboundFormatError.unsupportedVersion }
            guard case .object? = params["capabilities"], case .object? = params["clientInfo"] else {
                throw MCPInboundFormatError.invalidParameters
            }
            return .initialize(id, version)
        case "ping":
            guard params.isEmpty else { throw MCPInboundFormatError.invalidParameters }
            return .ping(id)
        case "tools/list":
            guard params.isEmpty else { throw MCPInboundFormatError.invalidParameters }
            return .listTools(id)
        case "tools/call":
            guard Set(params.keys).isSubset(of: ["name", "arguments"]),
                  let name = params["name"]?.stringValue,
                  case .object(let arguments)? = params["arguments"] else { throw MCPInboundFormatError.invalidParameters }
            if name == "mika_task_status" || name == "mika_cancel_task" {
                guard Set(arguments.keys) == ["task_id"], let taskID = try optionalUUID(arguments["task_id"]) else {
                    throw MCPInboundFormatError.invalidParameters
                }
                return name == "mika_task_status" ? .taskStatus(id, taskID) : .cancelTask(id, taskID)
            }
            if name == "mika_wait_task" {
                guard Set(arguments.keys).isSubset(of: ["task_id", "timeout_s"]),
                      let taskID = try optionalUUID(arguments["task_id"]) else { throw MCPInboundFormatError.invalidParameters }
                let timeout = try boundedInteger(arguments["timeout_s"], defaultValue: 30, maximum: 50)
                return .waitTask(id, taskID, timeout)
            }
            if name == "mika_answer" || name == "mika_steer_task" {
                let keys: Set<String> = name == "mika_answer" ? ["task_id", "question_id", "request_id", "text"] : ["task_id", "request_id", "text"]
                guard Set(arguments.keys) == keys, let taskID = try optionalUUID(arguments["task_id"]),
                      let requestID = try optionalUUID(arguments["request_id"]), let raw = arguments["text"]?.stringValue else {
                    throw MCPInboundFormatError.invalidParameters
                }
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let maximum = name == "mika_answer" ? 2000 : 4000
                guard !text.isEmpty, text.utf16.count <= maximum else { throw MCPInboundFormatError.invalidParameters }
                if name == "mika_answer" {
                    guard let questionID = try optionalUUID(arguments["question_id"]) else { throw MCPInboundFormatError.invalidParameters }
                    return .answerTask(id, taskID, questionID, requestID, text)
                }
                return .steerTask(id, taskID, requestID, text)
            }
            if name == "mika_list_tasks" {
                guard Set(arguments.keys).isSubset(of: ["limit"]) else { throw MCPInboundFormatError.invalidParameters }
                let limit = try boundedInteger(arguments["limit"], defaultValue: 10, maximum: 50)
                return .listTasks(id, limit)
            }
            guard name == "mika_run_task",
                  Set(arguments.keys).isSubset(of: ["goal", "request_id", "conversation"]),
                  let raw = arguments["goal"]?.stringValue else { throw MCPInboundFormatError.invalidParameters }
            let goal = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Kotlin String.length is UTF-16 code units, not Swift graphemes.
            guard !goal.isEmpty, goal.utf16.count <= 4_000 else { throw MCPInboundFormatError.invalidParameters }
            let requestID = try optionalUUID(arguments["request_id"])
            var conversation: String?
            if let value = arguments["conversation"], value != .null {
                guard let text = value.stringValue, text.hasPrefix("mcp-"),
                      let uuid = UUID(uuidString: String(text.dropFirst(4))),
                      text == "mcp-" + uuid.uuidString.lowercased() else { throw MCPInboundFormatError.invalidParameters }
                conversation = text
            }
            return .runTask(id, MCPInboundModelTask(goal: goal, requestID: requestID, conversation: conversation))
        default: throw MCPInboundFormatError.unsupportedMethod
        }
    }

    private static func boundedInteger(_ input: JSONValue?, defaultValue: Int, maximum: Int) throws -> Int {
        guard let input else { return defaultValue }
        guard case .number(let number) = input, number >= 1, number <= Decimal(maximum) else { throw MCPInboundFormatError.invalidParameters }
        let value = NSDecimalNumber(decimal: number).intValue
        guard Decimal(value) == number else { throw MCPInboundFormatError.invalidParameters }
        return value
    }
    private static func optionalUUID(_ value: JSONValue?) throws -> UUID? {
        guard let value else { return nil }
        guard let text = value.stringValue, let uuid = UUID(uuidString: text),
              text == uuid.uuidString.lowercased() else { throw MCPInboundFormatError.invalidParameters }
        return uuid
    }
}

/// Bounded strict JSON reader rejects duplicate keys (including escaped aliases),
/// trailing bytes, invalid UTF-8 and excessive nesting before interpretation.
private struct StrictJSON {
    let bytes: [UInt8]
    private var index = 0
    private var nodes = 0
    init(bytes: [UInt8]) { self.bytes = bytes }
    mutating func parse() throws -> JSONValue {
        guard String(bytes: bytes, encoding: .utf8) != nil else { throw MCPInboundFormatError.malformed }
        let result = try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw MCPInboundFormatError.malformed }
        return result
    }
    private mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    private mutating func value(depth: Int) throws -> JSONValue {
        whitespace(); nodes += 1
        guard depth <= 16, nodes <= 512, index < bytes.count else { throw MCPInboundFormatError.malformed }
        switch bytes[index] {
        case 123:
            index += 1; whitespace(); var result: [String: JSONValue] = [:]
            if take(125) { return .object(result) }
            while true {
                whitespace(); let key = try string()
                guard result[key] == nil else { throw MCPInboundFormatError.malformed }
                whitespace(); guard take(58) else { throw MCPInboundFormatError.malformed }
                result[key] = try value(depth: depth + 1)
                whitespace(); if take(125) { return .object(result) }
                guard take(44) else { throw MCPInboundFormatError.malformed }
            }
        case 91:
            index += 1; whitespace(); var result: [JSONValue] = []
            if take(93) { return .array(result) }
            while true {
                result.append(try value(depth: depth + 1))
                whitespace(); if take(93) { return .array(result) }
                guard take(44) else { throw MCPInboundFormatError.malformed }
            }
        case 34: return .string(try string())
        default:
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            guard index > start, let result = try? JSONDecoder().decode(JSONValue.self, from: Data(bytes[start..<index])) else {
                throw MCPInboundFormatError.malformed
            }
            switch result {
            case .number, .bool, .null: return result
            default: throw MCPInboundFormatError.malformed
            }
        }
    }
    private mutating func string() throws -> String {
        guard index < bytes.count, bytes[index] == 34 else { throw MCPInboundFormatError.malformed }
        let start = index; index += 1; var escaped = false
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if escaped { escaped = false; continue }
            if byte == 92 { escaped = true; continue }
            if byte == 34 {
                guard let result = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else {
                    throw MCPInboundFormatError.malformed
                }
                return result
            }
        }
        throw MCPInboundFormatError.malformed
    }
    private mutating func take(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
}

/// Identifiers are host-provided revision/connection handles, not authentication.
/// The host must independently authenticate the peer and revalidate these handles
/// atomically at transport and execution boundaries.
public struct MCPInboundReviewBinding: Sendable, Equatable {
    public let connection: UUID
    public let destinationRevision: UUID
    public let contextRevision: UUID
    public init(connection: UUID, destinationRevision: UUID, contextRevision: UUID) {
        self.connection = connection; self.destinationRevision = destinationRevision; self.contextRevision = contextRevision
    }
}

/// Immutable snapshot for a future local review UI. It contains untrusted text;
/// displaying it is not approval and its contents must not be logged.
public struct MCPInboundReview: Sendable, Equatable {
    public let id: UUID
    public let binding: MCPInboundReviewBinding
    public let task: MCPInboundModelTask
}

/// In-memory review state only. No listening, storage, task dispatch or model call.
/// Actor isolation serializes transitions within this instance, not across hosts.
public actor MCPInboundReviewState {
    private enum State {
        case idle
        case pending(UUID, MCPInboundReviewBinding, MCPInboundModelTask)
        case approved(UUID, MCPInboundReviewBinding, MCPInboundModelTask)
    }
    private var enabled = false
    private var active = false
    private var state: State = .idle
    public init() {}

    /// These calls must come from local user/lifecycle controls, never remote RPC.
    public func setEnabledByUser(_ value: Bool) { enabled = value; state = .idle }
    public func setForegroundActive(_ value: Bool) { active = value; if !value { state = .idle } }
    public func discard() { state = .idle }

    /// Replaces any previous review, including a previously approved grant.
    public func stage(_ task: MCPInboundModelTask, binding: MCPInboundReviewBinding) -> MCPInboundReview? {
        guard enabled && active else { state = .idle; return nil }
        let ticket = UUID(); state = .pending(ticket, binding, task)
        return MCPInboundReview(id: ticket, binding: binding, task: task)
    }
    /// Approval is a local action on the displayed immutable task and binding.
    public func approveLocally(ticket: UUID, current: MCPInboundReviewBinding) -> UUID? {
        guard enabled, active, case .pending(let expected, let binding, let task) = state,
              expected == ticket, binding == current else { state = .idle; return nil }
        let grant = UUID(); state = .approved(grant, binding, task); return grant
    }
    /// A grant is consumed once. It does not provide durable replay protection.
    public func consume(grant: UUID, current: MCPInboundReviewBinding) -> MCPInboundModelTask? {
        defer { state = .idle }
        guard enabled, active, case .approved(let expected, let binding, let task) = state,
              expected == grant, binding == current else { return nil }
        return task
    }
}
