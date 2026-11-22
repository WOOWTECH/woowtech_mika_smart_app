#if !MCP_SMOKE
import Foundation
import XCTest
@testable import AssistantMCP

final class MCPDispatchDiagnosticTests: XCTestCase {
    private typealias Event = MCPConversationRunner.DispatchDiagnostic

    /// All access to the synchronous observer's storage is covered by the lock.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Event] = []
        func append(_ event: Event) { lock.lock(); defer { lock.unlock() }; storage.append(event) }
        var events: [Event] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private actor Executor: MCPConversationExecuting {
        var replies: [Result<JSONValue, Error>]
        private(set) var calls: [MCPConversationAction] = []
        init(_ replies: [Result<JSONValue, Error>]) { self.replies = replies }
        func callAuthorizedTool(name: String, arguments: JSONValue) async throws -> JSONValue {
            calls.append(.callTool(name: name, arguments: arguments))
            return try reply()
        }
        func readResource(uri: String) async throws -> JSONValue {
            calls.append(.readResource(uri: uri))
            return try reply()
        }
        private func reply() throws -> JSONValue {
            guard !replies.isEmpty else { throw MCPConversationChecks.Failure.secret }
            return try replies.removeFirst().get()
        }
        nonisolated func serverName(of action: MCPConversationAction) -> String? { "PRIVATE_SERVER_NAME" }
    }

    private func run(_ model: MCPConversationChecks.Model, executor: any MCPConversationExecuting,
                     diagnostics: Recorder, events: MCPConversationChecks.Record = .init(),
                     resources: [MCPResource] = []) async throws -> MCPConversationResult {
        try await MCPConversationRunner(client: model, observeDispatch: { diagnostics.append($0) }).run(
            messages: [.init(role: "user", content: "Run the selected fixture operation once.")],
            configuration: MCPConversationChecks.configuration, apiKey: "fixture-not-a-key",
            tools: [MCPConversationChecks.tool], resources: resources, executor: executor,
            onEvent: { await events.event($0) })
    }

    private func assertTerminal(_ recorder: Recorder, phase: Event.Phase, expected: MCPExecutionDiagnostic,
                          file: StaticString = #filePath, line: UInt = #line) throws -> Event {
        let events = recorder.events
        XCTAssertEqual(events.count, 2, file: file, line: line)
        let started = try XCTUnwrap(events.first, file: file, line: line)
        let terminal = try XCTUnwrap(events.last, file: file, line: line)
        XCTAssertEqual(started.phase, .started, file: file, line: line)
        XCTAssertNil(started.diagnostic, file: file, line: line)
        XCTAssertEqual(terminal.id, started.id, file: file, line: line)
        XCTAssertEqual(terminal.phase, phase, file: file, line: line)
        XCTAssertEqual(terminal.diagnostic, expected, file: file, line: line)
        XCTAssertGreaterThanOrEqual(started.elapsedMilliseconds, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(terminal.elapsedMilliseconds, started.elapsedMilliseconds, file: file, line: line)
        // Check the exact string sent to Logger, not a parallel test formatter.
        let code = expected.code.map { String($0) } ?? "none"
        XCTAssertEqual(terminal.message,
            "dispatch=\(started.id.uuidString) phase=\(phase.rawValue) category=\(expected.category.rawValue) code=\(code) outcome_unknown=\(expected.outcomeUnknown) elapsed_ms=\(terminal.elapsedMilliseconds)",
            file: file, line: line)
        for event in events {
            for forbidden in ["fixture_echo", "hello", "fixture-not-a-key", "PRIVATE_SERVER_NAME",
                              "PRIVATE_SERVER_TEXT", "PRIVATE_CREDENTIAL", "private.invalid", "structuredContent", "completed"] {
                XCTAssertFalse(event.message.contains(forbidden), "Dispatch log contains payload or claims step completion", file: file, line: line)
            }
        }
        return terminal
    }

    func testReturnedResultsClassifyBeforeTerminalEventAndCannotReplay() async throws {
        let cases: [(JSONValue?, MCPExecutionDiagnostic.Category)] = [
            (nil, .result), (.bool(false), .result), (.bool(true), .toolError),
            (.string("false"), .protocolFailure), (.null, .protocolFailure),
            (.number(0), .protocolFailure), (.array([]), .protocolFailure), (.object([:]), .protocolFailure)
        ]
        for (flag, category) in cases {
            var fields: [String: JSONValue] = [
                "content": .array([.object(["type": .string("text"), "text": .string("PRIVATE_SERVER_TEXT")])]),
                // Server-supplied diagnostics, codes and credentials remain untrusted data.
                "diagnostic": .object(["category": .string("http"), "code": .number(401), "outcomeUnknown": .bool(false)]),
                "structuredContent": .object(["code": .number(-32602), "endpoint": .string("https://private.invalid"),
                                               "credential": .string("PRIVATE_CREDENTIAL")])
            ]
            fields["isError"] = flag
            let returned = JSONValue.object(fields)
            let executor = Executor([.success(returned)]), diagnostics = Recorder(), events = MCPConversationChecks.Record()
            let command = try MCPConversationChecks.call()
            let result = try await run(.init([command, command, MCPConversationChecks.finish]), executor: executor,
                                       diagnostics: diagnostics, events: events)
            let expected = MCPExecutionDiagnostic(category: category, outcomeUnknown: category != .result)
            let terminal = try assertTerminal(diagnostics, phase: .returned, expected: expected)
            XCTAssertEqual(result.stopReason, .finished)
            XCTAssertEqual(result.steps.count, 1)
            let step = try XCTUnwrap(result.steps.first)
            XCTAssertEqual(step.result, returned)
            XCTAssertEqual(step.isError, category != .result)
            XCTAssertEqual(step.diagnostic, terminal.diagnostic)
            let calls = await executor.calls, published = await events.events
            XCTAssertEqual(calls.count, 1, "The repeated command must never dispatch again")
            XCTAssertEqual(published.filter { if case .completed = $0 { return true }; return false }, [.completed(step)])
        }
    }

    func testNonObjectReturnLogsProtocolFailureAndStillThrowsWithoutCompletion() async throws {
        let invalidValues: [JSONValue] = [.null, .bool(false), .number(0), .string("PRIVATE_SERVER_TEXT"), .array([])]
        for value in invalidValues {
            let diagnostics = Recorder(), events = MCPConversationChecks.Record(), executor = Executor([.success(value)])
            do {
                _ = try await run(.init([try MCPConversationChecks.call()]), executor: executor,
                                  diagnostics: diagnostics, events: events)
                XCTFail("Invalid executor result must still throw")
            } catch let error as MCPConversationError { XCTAssertEqual(error, .invalidExecutionResult) }
            _ = try assertTerminal(diagnostics, phase: .returned, expected: .init(category: .protocolFailure, outcomeUnknown: true))
            let published = await events.events, calls = await executor.calls
            XCTAssertFalse(published.contains { if case .completed = $0 { return true }; return false })
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testThrownFailuresUseTypedCodesAndUncertaintyWithoutReplay() async throws {
        let cases: [(Error, MCPExecutionDiagnostic)] = [
            (MCPError.httpStatus(statusCode: 401), .init(category: .http, code: 401, outcomeUnknown: true)),
            (MCPError.httpStatus(statusCode: 500), .init(category: .http, code: 500, outcomeUnknown: true)),
            (MCPError.rpcFailure(rpcCode: -32602), .init(category: .rpc, code: -32602, outcomeUnknown: false)),
            (MCPError.rpcFailure(rpcCode: -32603), .init(category: .rpc, code: -32603, outcomeUnknown: true)),
            (MCPError.rpcFailure(rpcCode: -32000), .init(category: .rpc, code: -32000, outcomeUnknown: true)),
            (MCPError.timedOut, .init(category: .timeout, outcomeUnknown: true)),
            (MCPError.transportFailure, .init(category: .transport, outcomeUnknown: true)),
            (MCPError.invalidResponse, .init(category: .protocolFailure, outcomeUnknown: true)),
            (MCPError.cancelled, .init(category: .cancelled, outcomeUnknown: true)),
            (CancellationError(), .init(category: .cancelled, outcomeUnknown: true)),
            (NSError(domain: "https://private.invalid", code: 987,
                     userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SERVER_TEXT PRIVATE_CREDENTIAL"]),
             .init(category: .other, outcomeUnknown: true))
        ]
        for (failure, expected) in cases {
            let diagnostics = Recorder(), executor = Executor([.failure(failure)])
            let command = try MCPConversationChecks.call()
            let result = try await run(.init([command, command, MCPConversationChecks.finish]), executor: executor,
                                       diagnostics: diagnostics)
            let terminal = try assertTerminal(diagnostics, phase: .failed, expected: expected)
            XCTAssertEqual(result.stopReason, .finished)
            XCTAssertEqual(result.steps.count, 1)
            XCTAssertEqual(result.steps.first?.diagnostic, terminal.diagnostic)
            XCTAssertEqual(result.steps.first?.isError, true)
            let calls = await executor.calls
            XCTAssertEqual(calls.count, 1)
        }
    }

    func testResourceReturnUsesSameClassificationAndCorrelation() async throws {
        let resource = MCPResource(uri: "https://private.invalid/resource", name: "PRIVATE_SERVER_NAME")
        let diagnostics = Recorder(), executor = Executor([.success(.object(["contents": .array([])]))])
        let command = #"{"action":"read_resource","uri":"https://private.invalid/resource"}"#
        let result = try await run(.init([command, MCPConversationChecks.finish]), executor: executor,
                                   diagnostics: diagnostics, resources: [resource])
        let terminal = try assertTerminal(diagnostics, phase: .returned, expected: .init(category: .result, outcomeUnknown: false))
        XCTAssertEqual(result.steps.first?.diagnostic, terminal.diagnostic)
        let calls = await executor.calls
        XCTAssertEqual(calls, [.readResource(uri: resource.uri)])
    }

    func testThirdConsecutiveFailureHasTerminalDiagnosticBeforeExistingCutoff() async throws {
        let commands = try (0..<3).map { try MCPConversationChecks.call(.object(["text": .string("\($0)")])) }
        let diagnostics = Recorder(), events = MCPConversationChecks.Record()
        let executor = Executor(Array(repeating: .failure(MCPError.timedOut), count: 3))
        do {
            _ = try await run(.init(commands + [MCPConversationChecks.finish]), executor: executor,
                              diagnostics: diagnostics, events: events)
            XCTFail("The third consecutive executor failure must still stop the run")
        } catch let error as MCPConversationError { XCTAssertEqual(error, .executionFailed) }
        let logged = diagnostics.events, published = await events.events, calls = await executor.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(logged.count, 6)
        let starts = logged.filter { $0.phase == .started }, terminals = logged.filter { $0.phase != .started }
        XCTAssertEqual(Set(starts.map(\.id)).count, 3)
        XCTAssertEqual(terminals.map(\.id), starts.map(\.id))
        XCTAssertEqual(terminals.map(\.phase), [.failed, .failed, .failed])
        XCTAssertTrue(terminals.allSatisfy { $0.diagnostic == .init(category: .timeout, outcomeUnknown: true) })
        XCTAssertEqual(published.filter { if case .completed = $0 { return true }; return false }.count, 2)
    }

    func testReturnedToolErrorStillResetsThrownFailureStreak() async throws {
        let commands = try (0..<5).map { try MCPConversationChecks.call(.object(["text": .string("\($0)")])) }
        let failure = Result<JSONValue, Error>.failure(MCPError.timedOut)
        let executor = Executor([failure, failure, .success(.object(["isError": .bool(true)])), failure, failure])
        let diagnostics = Recorder()
        let result = try await run(.init(commands + [MCPConversationChecks.finish]), executor: executor, diagnostics: diagnostics)
        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.steps.count, 5)
        let terminals = diagnostics.events.filter { $0.phase != .started }
        XCTAssertEqual(terminals.map(\.phase), [.failed, .failed, .returned, .failed, .failed])
        XCTAssertEqual(terminals.map { $0.diagnostic?.category }, [.timeout, .timeout, .toolError, .timeout, .timeout])
    }

    func testLateExecutorReturnAfterCancellationIsNotPublishedAsCompletedStep() async throws {
        let diagnostics = Recorder(), events = MCPConversationChecks.Record(), gate = MCPConversationChecks.Gate()
        let executor = MCPConversationChecks.Executor(gate: gate)
        let model = MCPConversationChecks.Model([try MCPConversationChecks.call(), MCPConversationChecks.finish])
        let terminalObserved = expectation(description: "Late executor return is diagnosed")
        let runner = MCPConversationRunner(client: model, observeDispatch: { event in
            diagnostics.append(event)
            if event.phase != .started { terminalObserved.fulfill() }
        })
        let task = Task {
            try await runner.run(messages: [.init(role: "user", content: "Run once.")],
                configuration: MCPConversationChecks.configuration, apiKey: "fixture-not-a-key",
                tools: [MCPConversationChecks.tool], executor: executor, onEvent: { await events.event($0) })
        }
        try await gate.waitUntilEntered()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must still propagate") }
        catch is CancellationError { }
        await gate.release(true)
        await fulfillment(of: [terminalObserved], timeout: 2)
        _ = try assertTerminal(diagnostics, phase: .returned, expected: .init(category: .result, outcomeUnknown: false))
        // As in the existing cancellation fixture, let any late callback drain.
        try await Task.sleep(nanoseconds: 20_000_000)
        let published = await events.events, calls = await executor.calls
        XCTAssertFalse(published.contains { if case .completed = $0 { return true }; return false })
        XCTAssertEqual(calls.count, 1)
    }
}
#endif
