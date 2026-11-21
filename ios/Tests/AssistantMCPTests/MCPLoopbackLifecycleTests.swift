#if !MCP_SMOKE
import Foundation
import XCTest
@testable import AssistantMCP

/// Exercises the production HTTP transport/parser and conversation runner over
/// actual loopback sockets. The executor adapter avoids weakening MCPClient's
/// HTTPS requirement. MCPClient session negotiation is covered separately.
final class MCPLoopbackLifecycleTests: XCTestCase {
    private actor Executor: MCPConversationExecuting {
        let endpoint: URL
        let timeout: Duration
        let transport = MCPHTTPTransport(configuration: .ephemeral)
        private(set) var failures: [MCPError] = []

        init(endpoint: URL, timeout: Duration = .seconds(3)) {
            self.endpoint = endpoint; self.timeout = timeout
        }

        func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
            try await send("tools/call", params: .object(["name": .string(name), "arguments": arguments]))
        }

        func readResource(uri: String) async throws -> JSONValue {
            try await send("resources/read", params: .object(["uri": .string(uri)]))
        }

        private func send(_ method: String, params: JSONValue) async throws -> JSONValue {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(JSONValue.object([
                "jsonrpc": .string("2.0"), "id": .string("fixture-id"),
                "method": .string(method), "params": params
            ]))
            do {
                let reply = try await transport.send(request, expectedID: "fixture-id",
                                                     deadline: .now.advanced(by: timeout))
                guard let result = reply.result else { throw MCPError.invalidResponse }
                return result
            } catch {
                let safe = MCPError.sanitized(error)
                failures.append(safe)
                throw safe
            }
        }

        func waitForFailure() async throws {
            for _ in 0..<500 {
                if !failures.isEmpty { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            throw MCPClientChecks.Failed(check: "cancelled HTTP operation did not finish")
        }
    }

    private func run(_ model: MCPConversationChecks.Model, executor: Executor,
                     record: MCPConversationChecks.Record = .init()) async throws -> MCPConversationResult {
        try await MCPConversationRunner(client: model).run(
            messages: [.init(role: "user", content: "Run the selected fixture operation once.")],
            configuration: MCPConversationChecks.configuration, apiKey: "fixture-not-a-key",
            tools: [MCPConversationChecks.tool], executor: executor,
            limits: .init(timeout: .seconds(10)), onEvent: { await record.event($0) })
    }

    private func assertSafeDiagnostic(_ value: MCPExecutionDiagnostic?, category: MCPExecutionDiagnostic.Category,
                                      code: Int? = nil, unknown: Bool, endpoint: URL,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let diagnostic = try XCTUnwrap(value, file: file, line: line)
        XCTAssertEqual(diagnostic.category, category, file: file, line: line)
        XCTAssertEqual(diagnostic.code, code, file: file, line: line)
        XCTAssertEqual(diagnostic.outcomeUnknown, unknown, file: file, line: line)
        let description = String(reflecting: diagnostic)
        for forbidden in [endpoint.absoluteString, "PRIVATE_FIXTURE_BODY", "FIXTURE_TOOL_REFUSAL",
                          "fixture_echo", "fixture-not-a-key", "hello", "structuredContent"] {
            // Assert a boolean to avoid printing a potentially unsafe value on failure.
            XCTAssertFalse(description.contains(forbidden), "Diagnostic must contain no payload", file: file, line: line)
        }
    }

    func testHTTPToolErrorIsDistinctFromHTTPAndRPCFailuresWithoutReplay() async throws {
        let cases: [(MCPLoopbackHTTPFixture.Reply, MCPError?, Bool)] = [
            (.toolError, nil, true), (.http(401), .httpStatus(statusCode: 401), true),
            (.http(500), .httpStatus(statusCode: 500), true),
            (.rpc(-32602), .rpcFailure(rpcCode: -32602), false),
            (.rpc(-32603), .rpcFailure(rpcCode: -32603), true),
            (.rpc(-32000), .rpcFailure(rpcCode: -32000), true)
        ]
        for (reply, expectedFailure, unknown) in cases {
            let server = try MCPLoopbackHTTPFixture([reply])
            defer { server.stop() }
            let endpoint = try await server.start()
            let executor = Executor(endpoint: endpoint)
            let command = try MCPConversationChecks.call()
            // Even a model asking to repeat the failed call cannot replay it.
            let model = MCPConversationChecks.Model([command, command, MCPConversationChecks.finish])
            let record = MCPConversationChecks.Record()
            let result = try await run(model, executor: executor, record: record)
            XCTAssertEqual(result.stopReason, .finished)
            XCTAssertEqual(result.steps.count, 1)
            XCTAssertTrue(result.steps.first?.isError == true)
            XCTAssertEqual(server.receivedMethods, ["tools/call"])
            let failures = await executor.failures
            XCTAssertEqual(failures, expectedFailure.map { [$0] } ?? [])
            let category: MCPExecutionDiagnostic.Category
            let code: Int?
            switch expectedFailure {
            case .httpStatus(let status)?: category = .http; code = status
            case .rpcFailure(let rpcCode)?: category = .rpc; code = rpcCode
            default: category = .toolError; code = nil
            }
            try assertSafeDiagnostic(result.steps.first?.diagnostic, category: category,
                                     code: code, unknown: unknown, endpoint: endpoint)
            let dispatched = await record.dispatched
            XCTAssertEqual(dispatched.count, 1)
            let inputs = await model.inputs
            let feedback = inputs[1].last?.content ?? ""
            // UI metadata also warns for a returned tool error, but the model
            // still receives that actual server result without synthetic text.
            let syntheticUnknown = expectedFailure != nil && unknown
            XCTAssertEqual(feedback.contains("is unknown"), syntheticUnknown)
            XCTAssertEqual(feedback.contains("do not send it again"), syntheticUnknown)
            XCTAssertFalse(feedback.contains("PRIVATE_FIXTURE_BODY"))
            XCTAssertFalse(feedback.contains(endpoint.absoluteString))
            if expectedFailure == nil {
                XCTAssertTrue(feedback.contains("FIXTURE_TOOL_REFUSAL"), "Actual tool error content is preserved")
                let payload = try JSONDecoder().decode(JSONValue.self,
                    from: Data(feedback.dropFirst(MCPConversationRunner.resultPrefix.count).utf8))
                XCTAssertTrue(payload["result"] == result.steps.first?.result, "Actual server result reaches the model unchanged")
                XCTAssertNil(payload["diagnostic"], "Trusted UI metadata is separate from the model payload")
                XCTAssertTrue(result.steps.first?.result["diagnostic"]?["code"] == .number(401),
                              "Server fields remain data and cannot supply trusted diagnostic codes")
            }
            if case .rpc = reply {
                XCTAssertFalse(feedback.contains("before a result arrived"), "A matched RPC error is a server response")
                if unknown { XCTAssertTrue(feedback.contains("Whether changes were applied is unknown")) }
                else { XCTAssertTrue(feedback.contains("invalid params")) }
            }
        }
    }

    func testHTTPTimeoutAndDisconnectKeepUnknownOutcomeAndAllowFreshRead() async throws {
        for reply in [MCPLoopbackHTTPFixture.Reply.holdBeforeHeaders, .holdSSE, .disconnect] {
            let server = try MCPLoopbackHTTPFixture([reply, .ok])
            defer { server.stop() }
            let endpoint = try await server.start()
            let executor = Executor(endpoint: endpoint, timeout: .seconds(1))
            let command = try MCPConversationChecks.call()
            let model = MCPConversationChecks.Model([command, command, MCPConversationChecks.finish])
            let result = try await run(model, executor: executor)
            XCTAssertEqual(result.steps.count, 1)
            XCTAssertTrue(result.steps.first?.isError == true)
            let failures = await executor.failures
            XCTAssertEqual(failures.count, 1)
            let category: MCPExecutionDiagnostic.Category
            if case .disconnect = reply {
                // Foundation versions expose a short HTTP body as either a
                // network loss or an incomplete protocol response.
                XCTAssertTrue(failures.first == .transportFailure || failures.first == .invalidResponse)
                category = failures.first == .transportFailure ? .transport : .protocolFailure
            } else {
                XCTAssertEqual(failures, [.timedOut])
                category = .timeout
            }
            try assertSafeDiagnostic(result.steps.first?.diagnostic, category: category, unknown: true, endpoint: endpoint)
            let inputs = await model.inputs
            let feedback = inputs[1].last?.content ?? ""
            XCTAssertTrue(feedback.contains("outcome is unknown") && feedback.contains("do not send it again"))
            XCTAssertEqual(server.receivedMethods, ["tools/call"])
            // A new read after the failed write uses the same URLSession and a
            // fresh HTTP connection. Recovery never resends the original call.
            let read = try await executor.readResource(uri: "fixture://status")
            XCTAssertTrue(read["isError"] == .bool(false))
            XCTAssertEqual(server.receivedMethods, ["tools/call", "resources/read"])
        }
    }

    func testHTTPResultMetadataCannotSpoofClassificationAndUnclassifiedStepsStayUnknown() async throws {
        for reply in [MCPLoopbackHTTPFixture.Reply.ok, .malformedIsError] {
            let server = try MCPLoopbackHTTPFixture([reply])
            defer { server.stop() }
            let endpoint = try await server.start()
            let executor = Executor(endpoint: endpoint)
            let command = try MCPConversationChecks.call()
            let model = MCPConversationChecks.Model([command, command, MCPConversationChecks.finish])
            let result = try await run(model, executor: executor)
            let step = try XCTUnwrap(result.steps.first)
            XCTAssertEqual(result.steps.count, 1)
            let malformed: Bool
            if case .malformedIsError = reply { malformed = true } else { malformed = false }
            XCTAssertEqual(step.isError, malformed)
            try assertSafeDiagnostic(step.diagnostic, category: malformed ? .protocolFailure : .result,
                                     unknown: malformed, endpoint: endpoint)
            let failures = await executor.failures
            XCTAssertTrue(failures.isEmpty, "Malformed tool flags are classified after an actual result")
            XCTAssertEqual(server.receivedMethods, ["tools/call"])
            // A legacy/unclassified record has no trusted evidence. Its payload,
            // including apparently diagnostic keys, must not fill that gap.
            let unclassified = MCPConversationStep(proposal: step.proposal, result: step.result, isError: step.isError)
            XCTAssertNil(unclassified.diagnostic)
        }
    }

    func testHTTPResponseLimitAndTruncatedToolErrorRetainSafeClassification() async throws {
        for reply in [MCPLoopbackHTTPFixture.Reply.oversizedResponse, .largeToolError] {
            let server = try MCPLoopbackHTTPFixture([reply])
            defer { server.stop() }
            let endpoint = try await server.start()
            let executor = Executor(endpoint: endpoint, timeout: .seconds(5))
            let command = try MCPConversationChecks.call()
            let model = MCPConversationChecks.Model([command, command, MCPConversationChecks.finish])
            let result = try await run(model, executor: executor)
            let step = try XCTUnwrap(result.steps.first)
            XCTAssertEqual(result.steps.count, 1)
            XCTAssertTrue(step.isError)
            XCTAssertEqual(server.receivedMethods, ["tools/call"])
            let failures = await executor.failures
            let inputs = await model.inputs
            let feedback = inputs[1].last?.content ?? ""
            if case .oversizedResponse = reply {
                XCTAssertEqual(failures, [.responseTooLarge])
                try await server.waitForRequests(1, includingResponse: true)
                let writes = server.completedResponseWrites
                XCTAssertEqual(writes.count, 1)
                XCTAssertEqual(writes.byteCount, 96, "95 header bytes plus one body byte; no oversized body")
                try assertSafeDiagnostic(step.diagnostic, category: .protocolFailure, unknown: true, endpoint: endpoint)
                XCTAssertTrue(feedback.contains("outcome is unknown") && feedback.contains("do not send it again"))
            } else {
                XCTAssertTrue(failures.isEmpty)
                try assertSafeDiagnostic(step.diagnostic, category: .toolError, unknown: true, endpoint: endpoint)
                XCTAssertTrue(step.result["truncated"] == .bool(true))
                XCTAssertEqual(step.result["text"]?.stringValue?.count, MCPConversationRunner.keptResultCharacters)
                let payload = try JSONDecoder().decode(JSONValue.self,
                    from: Data(feedback.dropFirst(MCPConversationRunner.resultPrefix.count).utf8))
                XCTAssertTrue(payload["isError"] == .bool(true) && payload["truncated"] == .bool(true))
                XCTAssertEqual(payload["text"]?.stringValue?.count, MCPConversationRunner.previewCharacters)
                XCTAssertFalse(feedback.contains("do not send it again"), "The bounded actual result is not replaced by synthetic text")
                XCTAssertNil(payload["diagnostic"])
            }
        }
    }

    func testHTTPCancellationAfterReceiptHasNoLateCompletionOrReplay() async throws {
        for reply in [MCPLoopbackHTTPFixture.Reply.holdBeforeHeaders, .holdSSE] {
            let server = try MCPLoopbackHTTPFixture([reply, .ok])
            defer { server.stop() }
            let endpoint = try await server.start()
            let executor = Executor(endpoint: endpoint)
            let model = MCPConversationChecks.Model([try MCPConversationChecks.call(), MCPConversationChecks.finish])
            let record = MCPConversationChecks.Record()
            let worker = Task { try await self.run(model, executor: executor, record: record) }
            defer { worker.cancel() }
            // For SSE, wait for the fixture's response write as well as full
            // request receipt; this does not claim the client consumed a frame.
            let waitForResponse: Bool
            if case .holdSSE = reply { waitForResponse = true } else { waitForResponse = false }
            try await server.waitForRequests(1, includingResponse: waitForResponse)
            worker.cancel()
            do { _ = try await worker.value; XCTFail("Cancellation must finish the run") }
            catch is CancellationError { }
            try await executor.waitForFailure()
            let failures = await executor.failures
            XCTAssertEqual(failures, [.cancelled])
            let events = await record.events
            XCTAssertFalse(events.contains { if case .completed = $0 { return true }; return false })
            let inputs = await model.inputs
            XCTAssertEqual(inputs.count, 1)
            XCTAssertEqual(server.receivedMethods, ["tools/call"])
            _ = try await executor.readResource(uri: "fixture://status")
            XCTAssertEqual(server.receivedMethods, ["tools/call", "resources/read"])
        }
    }
}
#endif
