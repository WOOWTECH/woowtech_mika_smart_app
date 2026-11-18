import AssistantModels
import Foundation

/// A trusted host executor, bound to the same connection as the selected catalog.
/// Calls arrive only for selected tools and offered resources, without a per-call
/// approval. An error/cancellation cannot promise remote rollback;
/// implementations must not automatically retry or switch connections. Like
/// Android, a failed call becomes an error result the model reads; the runner
/// never resends it by itself.
public protocol MCPConversationExecuting: Sendable {
    func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue
    func readResource(uri: String) async throws -> JSONValue
}

extension MCPClient: MCPConversationExecuting {}

public enum MCPConversationAction: Codable, Equatable, Sendable {
    case callTool(name: String, arguments: JSONValue)
    case readResource(uri: String)
}

/// Value snapshot of one operation the model chose. The results list shows the
/// full action, not an abbreviated summary of its arguments.
public struct MCPConversationProposal: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let action: MCPConversationAction

    public init(id: UUID = UUID(), action: MCPConversationAction) {
        self.id = id; self.action = action
    }
}

public struct MCPConversationStep: Equatable, Sendable {
    public let proposal: MCPConversationProposal
    /// Exact bounded server result, including content/structuredContent/isError.
    public let result: JSONValue
    public let isError: Bool
}

public enum MCPConversationEvent: Sendable, Equatable {
    case requestingModel(Int)
    /// One bounded format correction for this conversation; no operation was
    /// accepted from the invalid response. Contains no model-generated content.
    case correctingCommand
    /// Dispatch intent, emitted before entering the executor; not proof that the
    /// server received anything. Cancellation may still prevent dispatch. Once
    /// entered, a call may reach the server without producing a completed event.
    case executing(MCPConversationProposal)
    case completed(MCPConversationStep)
}

public enum MCPConversationStopReason: String, Codable, Sendable {
    /// approvalDenied: the user declined a local memory or profile review.
    /// Remote MCP calls have no per-call approval to decline. toolError stays
    /// for saved conversations: like Android, a tool error now goes back to the
    /// model instead of stopping the run.
    case finished, approvalDenied, modelCallLimit, toolCallLimit, repeatedCall, toolError
    case localCallLimit
    /// The model started an offered step (a web task or the skill tools); the
    /// host runs it with MCPConversationResult.handoff.
    case handedOff
}

public struct MCPConversationResult: Sendable {
    /// Present only when a valid finish command is received. Limits/refusal/tool
    /// errors never synthesize a successful model answer.
    public let answer: String?
    public let steps: [MCPConversationStep]
    public let modelCallCount: Int
    public let stopReason: MCPConversationStopReason
    /// Only for handedOff.
    public let handoff: MCPConversationHandoffRequest?

    init(answer: String?, steps: [MCPConversationStep], modelCallCount: Int, stopReason: MCPConversationStopReason,
         handoff: MCPConversationHandoffRequest? = nil) {
        self.answer = answer; self.steps = steps; self.modelCallCount = modelCallCount
        self.stopReason = stopReason; self.handoff = handoff
    }
}

/// The chat reply that asked for the first MCP operation. A plain or memory chat
/// offers the MCP catalog (MCPCombinedCatalog.entryInstructions); its first MCP
/// command starts the runner, which executes it before asking the model again.
public struct MCPConversationEntry: Sendable {
    /// The command's exact text, without a surrounding code fence.
    public let command: String
    /// What the chat did before it in this request: memory and profile commands
    /// and the host's data-only results, as the model saw them.
    public let exchange: [ModelMessage]
    /// Model calls the chat made for this request, the entry's own included.
    /// They count toward the runner's model-call limit.
    public let modelCalls: Int
    /// The chat's one local search and one local change, already used or not.
    /// The runner's own allowance is what is left of them.
    public let searchedLocally: Bool
    public let mutatedLocally: Bool

    public init(command: String, exchange: [ModelMessage] = [], modelCalls: Int = 1,
                searchedLocally: Bool = false, mutatedLocally: Bool = false) {
        self.command = command; self.exchange = exchange; self.modelCalls = modelCalls
        self.searchedLocally = searchedLocally; self.mutatedLocally = mutatedLocally
    }

    /// The MCP command a chat reply consists of, without a surrounding code
    /// fence, or nil. Only the shape is checked here: the runner decides whether
    /// the tool or resource was offered, and gives fixed feedback if not.
    public static func command(in text: String) -> String? {
        let body = MCPConversationRunner.unfenced(text)
        guard body.utf8.count <= 24 * 1024, (try? RawCommandEnvelope.fields(in: body)) != nil,
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8)),
              case .object(let fields) = decoded, let action = fields["action"]?.stringValue else { return nil }
        switch action {
        case "call_tool":
            guard Set(fields.keys) == ["action", "name", "arguments"], fields["name"]?.stringValue?.isEmpty == false,
                  case .object? = fields["arguments"] else { return nil }
        case "read_resource":
            guard Set(fields.keys) == ["action", "uri"], fields["uri"]?.stringValue?.isEmpty == false else { return nil }
        default: return nil
        }
        return body
    }
}

/// A step the host can run after MCP in the same request (a web task or the
/// skill tools), offered like the chat offers it. The host supplies the
/// wording, the actions that start it and its exact command validator.
public struct MCPConversationHandoff: Sendable {
    public let instructions: String
    public let actions: Set<String>
    public let accepts: @Sendable (String) -> Bool

    public init(instructions: String, actions: Set<String>, accepts: @escaping @Sendable (String) -> Bool) {
        self.instructions = instructions; self.actions = actions; self.accepts = accepts
    }
}

/// The step the model started. Nothing of it ran in the MCP step.
public struct MCPConversationHandoffRequest: Sendable {
    /// Index into the offered handoffs.
    public let offer: Int
    /// The command's exact text.
    public let command: String
    /// The MCP step so far for the next step's conversation: the chat's earlier
    /// local steps, then each MCP command and its result as the model read it,
    /// oldest left out first beyond MCPConversationRunner.handoffExchangeBytes.
    public let exchange: [ModelMessage]
}

public struct MCPConversationLimits: Sendable {
    public let maximumModelCalls: Int
    /// Includes explicitly selected resource reads as well as tool calls.
    public let maximumToolCalls: Int
    public let timeout: Duration

    /// Android AgentLoop.DEFAULT_MAX_STEPS.
    public static let maximumSteps = 60
    public static let longestTimeout: Duration = .seconds(30 * 60)

    /// Like Android, a task has many steps and no short overall limit; the
    /// iOS run still ends after 30 minutes.
    public init(maximumModelCalls: Int = MCPConversationLimits.maximumSteps,
                maximumToolCalls: Int = MCPConversationLimits.maximumSteps,
                timeout: Duration = MCPConversationLimits.longestTimeout) {
        self.maximumModelCalls = maximumModelCalls
        self.maximumToolCalls = maximumToolCalls
        self.timeout = timeout
    }
}

/// Fixed categories only: never embed credentials, catalog, arguments, server
/// output or an underlying localizedDescription in a thrown error.
public enum MCPConversationError: String, Error, Sendable, Equatable, LocalizedError {
    case invalidInput, invalidCatalog, invalidLimits, invalidCommand, unknownTool, unknownResource
    case inputTooLarge, modelResponseTooLarge, outputTooLarge, invalidExecutionResult
    case modelFailed, executionFailed, timedOut
    case localUnavailable, invalidLocalResult, localLeaseExpired
    /// Provider request failures are distinct from the whole-conversation deadline.
    /// HTTP status numbers, bodies and underlying error descriptions are discarded.
    case modelTimedOut, modelTransportFailed, modelHTTPRejected, modelInvalidResponse, modelIncompleteResponse
    case modelAuthenticationRejected, modelRateLimited, modelServiceUnavailable, modelRequestRejected

    public var errorDescription: String? { "MCP conversation stopped: \(rawValue)." }
}
