import AssistantModels
import Foundation
#if !MCP_SMOKE
@testable import AssistantMCP
#endif

/// Several servers in one chat request, like Android: tool names, routing, a
/// server that is absent, limits, the chat's first command and the steps after
/// MCP. Synthetic model and executors only; no endpoint, key or network.
enum MCPServerCatalogChecks {
    typealias Checks = MCPClientChecks.Counter
    static let configuration = MCPConversationChecks.configuration
    static let schema: JSONValue = .object(["type": .string("object"), "properties": .object([
        "text": .object(["type": .string("string")])])])

    actor Server: MCPConversationExecuting {
        let label: String
        private(set) var calls: [MCPConversationAction] = []
        init(_ label: String) { self.label = label }
        func callAuthorizedTool(name: String, arguments: JSONValue) throws -> JSONValue {
            calls.append(.callTool(name: name, arguments: arguments))
            return .object(["isError": .bool(false), "content": .array([.object([
                "type": .string("text"), "text": .string(label + " " + name)])])])
        }
        func readResource(uri: String) throws -> JSONValue {
            calls.append(.readResource(uri: uri))
            return .object(["contents": .array([.object(["uri": .string(uri), "text": .string(label + " " + uri)])])])
        }
    }

    static func tool(_ name: String, _ description: String? = nil) -> MCPTool {
        MCPTool(name: name, description: description, inputSchema: schema)
    }

    static func command(_ fields: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(JSONValue.object(fields)), as: UTF8.self)
    }

    static func call(_ name: String, _ text: String = "hello") throws -> String {
        try command(["action": .string("call_tool"), "name": .string(name), "arguments": .object(["text": .string(text)])])
    }

    /// Android's mcpToolNames: plain names, safe characters, the 64-character
    /// short form and its digest, and the order of the server's list not mattering.
    static func naming() throws -> Int {
        var c = Checks()
        try c.expect(MCPToolNaming.names(server: "0a11ce00", tools: ["search_read"]) == ["mcp_0a11ce00__search_read"],
                     "plain name: mcp_<server>__<tool>")
        try c.expect(MCPToolNaming.safe("odoo.search-read 讀") == "odoo_search_read__", "each other code point becomes _")
        let clash = MCPToolNaming.names(server: "0a11ce00", tools: ["a.b", "a-b"])
        try c.expect(Set(clash).count == 2 && clash.allSatisfy { $0.hasPrefix("mcp_0a11ce00__a_b_") && $0.count == 26 },
                     "names that clash after replacing characters get the digest form")
        try c.expect(MCPToolNaming.names(server: "0a11ce00", tools: ["a-b", "a.b"]) == [clash[1], clash[0]],
                     "the server's order never changes a name")
        let long = String(repeating: "x", count: 80)
        let short = MCPToolNaming.names(server: "0a11ce00", tools: [long])[0]
        try c.expect(short.count == MCPToolNaming.maximumLength && short.hasPrefix("mcp_0a11ce00__xxx")
                     && short.dropFirst(55).first == "_" && short.suffix(8).allSatisfy(\.isHexDigit),
                     "a long name keeps 55 characters, then _ and eight hex digits")
        try c.expect(MCPToolNaming.names(server: "0a11ce00", tools: [long]) == [short], "the digest is stable")
        try c.expect(MCPToolNaming.names(server: "0b0b0b00", tools: ["search_read"]) != MCPToolNaming.names(server: "0a11ce00", tools: ["search_read"]),
                     "the same tool on two servers gets two names")
        return c.count
    }

    /// One catalog from several servers: the same tool name twice, calls routed
    /// to the owner under its own name, server names in the descriptions, the
    /// same resource URI twice, and the runner's limits.
    static func combinedRouting() async throws -> Int {
        var c = Checks()
        let odoo = Server("A"), helpdesk = Server("B")
        let catalog = MCPCombinedCatalog(servers: [
            MCPServerOffer(key: "0a11ce00", name: "Odoo", tools: [tool("search_read", "Read records.")],
                           resources: [MCPResource(uri: "doc://guide", name: "Guide")], executor: odoo),
            MCPServerOffer(key: "0b0b0b00", name: "Helpdesk \"2\"", tools: [tool("search_read")],
                           resources: [MCPResource(uri: "doc://guide", name: "Guide")], executor: helpdesk)])
        let names = catalog.tools.map(\.name)
        try c.expect(names == ["mcp_0a11ce00__search_read", "mcp_0b0b0b00__search_read"], "both servers' tools, in server order")
        try c.expect(catalog.tools[0].description == "Configured MCP server: \"Odoo\"; transport: HTTP.\nRead records.",
                     "Android's provenance line before the description")
        try c.expect(catalog.tools[1].description == "Configured MCP server: \"Helpdesk \\\"2\\\"\"; transport: HTTP.\n",
                     "the server name is JSON-quoted")
        try c.expect(catalog.resources.map(\.uri) == ["mcp_0a11ce00:doc://guide", "mcp_0b0b0b00:doc://guide"],
                     "a URI two servers share is told apart by the server")
        _ = try await catalog.callAuthorizedTool(name: names[1], arguments: .object([:]))
        _ = try await catalog.readResource(uri: "mcp_0a11ce00:doc://guide")
        let aCalls = await odoo.calls, bCalls = await helpdesk.calls
        try c.expect(bCalls == [.callTool(name: "search_read", arguments: .object([:]))], "the call reaches its owner under its own name")
        try c.expect(aCalls == [.readResource(uri: "doc://guide")], "the resource read reaches its owner with its own URI")
        try c.expect(catalog.owner(ofTool: names[1])?.server == "Helpdesk \"2\"" && catalog.owner(ofTool: names[1])?.tool == "search_read",
                     "the results list can name server and tool")
        do { _ = try await catalog.callAuthorizedTool(name: "search_read", arguments: .object([:])); throw MCPClientChecks.Failed(check: "bare name ran") }
        catch MCPError.toolNotAllowed { try c.expect(true, "a name outside the catalog never runs") }
        let single = MCPCombinedCatalog(servers: [MCPServerOffer(key: "0a11ce00", name: "Odoo", tools: [tool("t")],
                                                                 resources: [MCPResource(uri: "doc://guide", name: "Guide")], executor: odoo)])
        try c.expect(single.resources.map(\.uri) == ["doc://guide"], "a URI only one server offers keeps its form")
        let unnamed = MCPCombinedCatalog(servers: [MCPServerOffer(key: "0a11ce00", name: "", tools: [tool("t")],
                                                                  resources: [], executor: odoo)])
        try c.expect(unnamed.tools[0].description?.hasPrefix("Configured MCP server: \"MCP server\";") == true
                     && unnamed.owner(ofTool: unnamed.tools[0].name)?.server == "",
                     "an unnamed server has a fixed name for the model and stays unnamed for the App")
        try c.expect(MCPCombinedCatalog(servers: []).isEmpty, "no server, nothing offered")
        // More than the runner accepts: the first 256 tools, in server order.
        let wide = (0..<200).map { tool("tool_\($0)") }
        let full = MCPCombinedCatalog(servers: [
            MCPServerOffer(key: "0a11ce00", name: "A", tools: wide, resources: [], executor: odoo),
            MCPServerOffer(key: "0b0b0b00", name: "B", tools: wide, resources: [], executor: helpdesk)])
        try c.expect(full.tools.count == MCPCombinedCatalog.maximumTools && full.omitted == 144
                     && full.tools.last?.name == "mcp_0b0b0b00__tool_55", "past 256 tools, the rest are left out and counted")
        let model = MCPConversationChecks.Model([try call(full.tools.last!.name), #"{"action":"finish","answer":"done"}"#])
        let result = try await MCPConversationRunner(client: model).run(
            messages: [.init(role: "user", content: "Use the last tool.")], configuration: configuration, apiKey: "fixture",
            tools: full.tools, resources: full.resources, executor: full)
        try c.expect(result.stopReason == .finished && result.steps.count == 1, "the runner accepts the combined catalog at its limit")
        let offer = full.entryInstructions() ?? ""
        try c.expect(offer.hasPrefix(MCPCombinedCatalog.entryLead) && offer.contains(full.catalogJSON() ?? "missing"),
                     "the chat offer carries the catalog the runner sends")
        return c.count
    }

    /// The chat's first MCP command starts the runner without another model
    /// call, counts toward its limits, and an unknown name gets fixed feedback.
    static func chatEntry() async throws -> Int {
        var c = Checks()
        let name = "mcp_0a11ce00__echo"
        let server = Server("A")
        let catalog = MCPCombinedCatalog(servers: [MCPServerOffer(key: "0a11ce00", name: "A", tools: [tool("echo")],
                                                                  resources: [], executor: server)])
        try c.expect(MCPConversationEntry.command(in: "```json\n" + (try call(name)) + "\n```") == (try call(name)),
                     "one fenced command is accepted, without its fence")
        try c.expect(MCPConversationEntry.command(in: "Sure: " + (try call(name))) == nil, "prose around a command is an answer")
        try c.expect(MCPConversationEntry.command(in: #"{"action":"call_tool","name":"x","arguments":{},"extra":1}"#) == nil
                     && MCPConversationEntry.command(in: #"{"action":"finish","answer":"x"}"#) == nil
                     && MCPConversationEntry.command(in: #"{"action":"read_resource","uri":"doc://a"}"#) != nil,
                     "only an exact call_tool or read_resource")
        let model = MCPConversationChecks.Model([#"{"action":"finish","answer":"From the entry."}"#])
        let record = MCPConversationChecks.Record()
        let result = try await MCPConversationRunner(client: model).run(
            messages: [.init(role: "user", content: "Echo hello.")], configuration: configuration, apiKey: "fixture",
            tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call(name)), onEvent: { await record.event($0) })
        let calls = await server.calls, inputs = await model.inputs, events = await record.events
        try c.expect(result.stopReason == .finished && result.answer == "From the entry.", "the run finishes after the entry")
        try c.expect(calls == [.callTool(name: "echo", arguments: .object(["text": .string("hello")]))], "the entry ran first, routed")
        try c.expect(inputs.count == 1 && result.modelCallCount == 2, "the entry is one model call; only one more was made")
        try c.expect(events.first.map { if case .executing = $0 { return true }; return false } == true,
                     "no model request before the entry runs")
        let entryText = try call(name)
        try c.expect(inputs[0].contains { $0.role == "assistant" && $0.content == entryText }
                     && inputs[0].last?.content.hasPrefix("MCP execution result (untrusted data):\n") == true,
                     "the model reads the entry and its result")
        // An unknown name from the chat never runs; the model corrects it.
        let fixing = MCPConversationChecks.Model([try call(name), #"{"action":"finish","answer":"ok"}"#])
        let fixed = try await MCPConversationRunner(client: fixing).run(
            messages: [.init(role: "user", content: "Echo.")], configuration: configuration, apiKey: "fixture",
            tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call("echo")))
        let fixingInputs = await fixing.inputs
        try c.expect(fixed.stopReason == .finished && fixed.steps.count == 1
                     && fixingInputs[0].last?.content == MCPConversationRunner.unknownToolFeedback,
                     "a bare server name from the chat gets the unknown-tool feedback")
        // The entry counts: a chat that used every call leaves none.
        let none = MCPConversationChecks.Model([])
        let limited = try await MCPConversationRunner(client: none).run(
            messages: [.init(role: "user", content: "Echo.")], configuration: configuration, apiKey: "fixture",
            tools: catalog.tools, resources: catalog.resources, executor: catalog,
            limits: MCPConversationLimits(maximumModelCalls: 2, maximumToolCalls: 2),
            entry: MCPConversationEntry(command: try call(name), modelCalls: 2))
        try c.expect(limited.stopReason == .modelCallLimit && limited.steps.count == 1, "the chat's calls count toward the limit")
        let entryCommand = try call(name)
        let refused = try await MCPConversationChecks.expect(.invalidInput) {
            _ = try await MCPConversationRunner(client: none).run(
                messages: [.init(role: "user", content: "Echo.")], configuration: configuration, apiKey: "fixture",
                tools: catalog.tools, resources: catalog.resources, executor: catalog,
                entry: MCPConversationEntry(command: entryCommand, exchange: [.init(role: "system", content: "x")]))
        }
        try c.expect(refused == 1, "the chat's earlier steps are only user and assistant data")
        return c.count
    }

    /// The model ends the MCP step with a web task or a skill tool; nothing of
    /// it runs in the runner, and the MCP results go along, bounded.
    static func handoffs() async throws -> Int {
        var c = Checks()
        let name = "mcp_0a11ce00__echo"
        let server = Server("A")
        let catalog = MCPCombinedCatalog(servers: [MCPServerOffer(key: "0a11ce00", name: "A", tools: [tool("echo")],
                                                                  resources: [], executor: server)])
        let web = MCPConversationHandoff(instructions: "Web tasks: open a page.", actions: ["web_read_page", "web_navigate"],
                                         accepts: { $0.contains("https://") })
        let skills = MCPConversationHandoff(instructions: "Skill tools: search.", actions: ["skill_search"], accepts: { _ in true })
        let webCommand = #"{"action":"web_read_page","url":"https://example.org/news"}"#
        let model = MCPConversationChecks.Model([#"{"action":"web_read_page","url":"ftp://x"}"#, webCommand])
        let result = try await MCPConversationRunner(client: model).run(
            messages: [.init(role: "user", content: "Check the order, then read the news.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call(name)), handoffs: [web, skills])
        let inputs = await model.inputs, calls = await server.calls
        try c.expect(result.stopReason == .handedOff && result.answer == nil && result.handoff?.offer == 0
                     && result.handoff?.command == webCommand, "the web command ends the MCP step for the host")
        try c.expect(calls.count == 1 && result.steps.count == 1, "only the MCP call ran")
        try c.expect(inputs[1].last?.content == MCPConversationRunner.formatFeedback, "a refused web command is a format slip")
        let system = inputs[0].first?.content ?? ""
        try c.expect(system.contains(MCPConversationRunner.handoffLead) && system.contains("Web tasks: open a page.")
                     && system.contains("Skill tools: search.") && system.contains(" besides the steps offered below."),
                     "the steps are offered after the MCP rules")
        let exchange = result.handoff?.exchange ?? []
        let entryText = try call(name)
        try c.expect(exchange.count == 2 && exchange[0] == ModelMessage(role: "assistant", content: entryText)
                     && exchange[1].content.hasPrefix("MCP execution result (untrusted data):\n"),
                     "the next step gets the MCP command and its result")
        let skill = MCPConversationChecks.Model([#"{"action":"skill_search","arguments":{"query":"orders"}}"#])
        let skillResult = try await MCPConversationRunner(client: skill).run(
            messages: [.init(role: "user", content: "Check the order with the skill.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call(name, "again")), handoffs: [skills])
        try c.expect(skillResult.handoff?.offer == 0 && skillResult.stopReason == .handedOff, "a skill tool ends the MCP step")
        let plain = MCPConversationChecks.Model([webCommand])
        let unoffered = try await MCPConversationRunner(client: plain).run(
            messages: [.init(role: "user", content: "Read the news.")], configuration: configuration, apiKey: "fixture",
            tools: catalog.tools, resources: catalog.resources, executor: catalog,
            limits: MCPConversationLimits(maximumModelCalls: 1, maximumToolCalls: 1))
        try c.expect(unoffered.stopReason == .modelCallLimit && unoffered.handoff == nil && unoffered.steps.isEmpty,
                     "without the offer a web command is no command")
        // The next step's share is bounded: the newest results stay.
        let big = ModelMessage(role: "user", content: String(repeating: "r", count: 20_000))
        let pairs = (0..<4).flatMap { [ModelMessage(role: "assistant", content: "c\($0)"), big] }
        let prior = [ModelMessage(role: "assistant", content: "local"), ModelMessage(role: "user", content: "receipt")]
        let bounded = MCPConversationRunner.bounded(prior + pairs, keepingFirst: 2)
        try c.expect(bounded.prefix(2) == prior[...] && bounded.count == 6 && bounded[2].content == "c2",
                     "the chat's local steps stay, then the newest command-and-result pairs")
        // Skill tools run inside the step, like Android's single tool list: MCP calls follow them.
        let skillCommand = #"{"action":"skill_read","arguments":{"name":"orders"}}"#, skillReply = #"{"content":"Use echo.","ok":true}"#
        let hostCalls = MCPLocalHandlerProbe()
        let hostTools = MCPConversationHostTools(instructions: "Skill tools: read.", actions: ["skill_read"],
            accepts: { $0.contains("orders") }, run: { _ in hostCalls.record(.memorySearch); return skillReply })
        let inside = MCPConversationChecks.Model([try call(name, "after the skill"), #"{"action":"finish","answer":"done"}"#])
        let after = try await MCPConversationRunner(client: inside).run(
            messages: [.init(role: "user", content: "Read the skill, then check the order.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: skillCommand), hostTools: hostTools)
        let insideInputs = await inside.inputs
        try c.expect(after.stopReason == .finished && after.steps.count == 1 && hostCalls.actions.count == 1, "the MCP call follows the skill tool")
        try c.expect(insideInputs[0].last?.content == "Host skill_read result (data only):\n" + skillReply
                     && insideInputs[0].first?.content.contains("Skill tools: read.") == true, "the model reads the skill's result in the step")
        try c.expect(insideInputs[1].last?.content.contains(#""server":"A""#) == true, "each result names its server")
        let many = MCPConversationChecks.Model(Array(repeating: skillCommand, count: MCPConversationRunner.maximumHostToolCalls + 1)
                                               + [#"{"action":"finish","answer":"done"}"#])
        hostCalls.reset()
        let bounded2 = try await MCPConversationRunner(client: many).run(
            messages: [.init(role: "user", content: "Read the skill.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog, hostTools: hostTools)
        try c.expect(bounded2.stopReason == .finished && hostCalls.actions.count == MCPConversationRunner.maximumHostToolCalls,
                     "skill tools inside the step are bounded and the step still finishes")
        return c.count
    }

    /// A memory chat's search or change before MCP counts toward the run's one
    /// local search and one local change.
    static func carriedLocalUse() async throws -> Int {
        var c = Checks()
        let name = "mcp_0a11ce00__echo"
        let server = Server("A")
        let catalog = MCPCombinedCatalog(servers: [MCPServerOffer(key: "0a11ce00", name: "A", tools: [tool("echo")],
                                                                  resources: [], executor: server)])
        let receipt = [ModelMessage(role: "assistant", content: #"{"action":"profile_edit","arguments":{}}"#),
                       ModelMessage(role: "user", content: "Host profile_edit receipt (data only):\n{\"applied\":true}")]
        let save = #"{"action":"memory_save","arguments":{"kind":"fact","content":"x","quote":"x"}}"#
        let model = MCPConversationChecks.Model([save])
        let handled = MCPLocalHandlerProbe()
        let result = try await MCPConversationRunner(client: model).run(
            messages: [.init(role: "user", content: "Remember x and check the order.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call(name), exchange: receipt, modelCalls: 2, mutatedLocally: true),
            handleLocal: { proposal, _ in handled.record(proposal.action); return .committedReceipt(json: #"{"ok":true}"#) })
        let inputs = await model.inputs
        try c.expect(result.stopReason == .localCallLimit && handled.actions.isEmpty, "no second local change after the chat's")
        try c.expect(inputs[0].contains(receipt[1]) && inputs[0].first?.content.contains(MCPConversationRunner.localMutationUsed) == true,
                     "the model sees the earlier receipt and that the change is used")
        try c.expect(result.modelCallCount == 3, "the chat's two calls and this one")
        // A refusal carried from the chat stands in the MCP step.
        let refusedModel = MCPConversationChecks.Model([save, #"{"action":"finish","answer":"Not saved."}"#])
        let refusedRun = try await MCPConversationRunner(client: refusedModel).run(
            messages: [.init(role: "user", content: "Remember x and check the order.")], configuration: configuration,
            apiKey: "fixture", tools: catalog.tools, resources: catalog.resources, executor: catalog,
            entry: MCPConversationEntry(command: try call(name, "refused"), refusedLocally: true),
            handleLocal: { proposal, _ in handled.record(proposal.action); return .committedReceipt(json: #"{"ok":true}"#) })
        let refusedInputs = await refusedModel.inputs
        try c.expect(refusedRun.stopReason == .finished && handled.actions.isEmpty, "the refused request offers no other local command")
        try c.expect(refusedInputs[0].first?.content.contains(MCPConversationRunner.localRefusalUsed) == true
                     && refusedInputs[1].last?.content == MCPConversationRunner.localRefusalStands, "the model hears that the refusal stands")
        return c.count
    }

    final class MCPLocalHandlerProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [MCPLocalAction] = []
        func record(_ action: MCPLocalAction) { lock.lock(); recorded.append(action); lock.unlock() }
        func reset() { lock.lock(); recorded = []; lock.unlock() }
        var actions: [MCPLocalAction] { lock.lock(); defer { lock.unlock() }; return recorded }
    }
}
