import Foundation

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var value: UInt64 = 1_000
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: UInt64) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
private actor SleepGate {
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var entered = 0
    private var cancelled: Set<UUID> = []
    func sleep(_ nanoseconds: UInt64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                Task { self.register(id, continuation) }
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func register(_ id: UUID, _ continuation: CheckedContinuation<Void, Error>) {
        if cancelled.remove(id) != nil { continuation.resume(throwing: CancellationError()); return }
        waiting[id] = continuation; entered += 1
    }
    private func cancel(_ id: UUID) {
        if let continuation = waiting.removeValue(forKey: id) { continuation.resume(throwing: CancellationError()) }
        else { cancelled.insert(id) }
    }
    func wakeAll() {
        let current = waiting.values; waiting.removeAll()
        for continuation in current { continuation.resume() }
    }
    func count() -> Int { entered }
}
@main enum InteractionChecks {
    struct Failure: Error { let label: String }
    static var count = 0
    static func check(_ value: Bool, _ label: String) throws { guard value else { throw Failure(label: label) }; count += 1 }
    static func rejects(_ error: MCPInboundAccessError, _ work: () async throws -> Void) async throws {
        do { try await work(); throw Failure(label: "unexpected success") }
        catch let actual as MCPInboundAccessError { try check(actual == error, "wrong rejection") }
    }
    static let key = String(repeating: "x", count: 43)
    static let headers = [MCPInboundHeader("Authorization", "Bearer " + key)]
    static let peer = MCPInboundPeer(addressBytes: [127,0,0,1])!
    static func parsedTask(_ id: UUID) throws -> MCPInboundModelTask {
        let args: [String: String] = ["goal":"summarize", "request_id":id.uuidString.lowercased()]
        let params: [String: Any] = ["name":"mika_run_task", "arguments":args]
        let root: [String: Any] = ["jsonrpc":"2.0", "id":1, "method":"tools/call", "params":params]
        guard case .runTask(_, let task) = try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: root)) else { throw Failure(label: "task parse") }
        return task
    }
    fileprivate static func setup(clock: TestClock = TestClock(), sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) async throws -> (MCPInboundAccessTasks, UUID, MCPInboundReviewBinding, UUID) {
        let core = MCPInboundAccessTasks(clock: { clock.read() }, sleep: sleep)
        await core.setForegroundActive(true)
        try await core.enableByUser(scope: .loopback, token: Data(key.utf8))
        let connection = try await core.open(peer: peer, headers: headers)
        let binding = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID())
        let id = UUID()
        guard case .review(let review) = try await core.stage(task: try parsedTask(id), binding: binding, peer: peer, headers: headers) else { throw Failure(label: "review") }
        _ = try await core.approveLocally(reviewID: review.id, current: binding)
        return (core, connection, binding, id)
    }
    fileprivate static func awaitSleeps(_ gate: SleepGate, _ expected: Int) async throws {
        let deadline = Date().addingTimeInterval(4)
        while await gate.count() < expected {
            if Date() > deadline { throw Failure(label: "sleep entry") }
            await Task.yield()
        }
    }
    static func interactions() async throws {
        let (core, connection, binding, id) = try await setup()
        let other = try await core.open(peer: peer, headers: headers)
        let changed = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: binding.contextRevision)
        try await rejects(.conflict) { _ = try await core.hostBegin(taskID: id, binding: changed) }
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "queued", connection: connection, peer: peer, headers: headers) }
        let lease = try await core.hostBegin(taskID: id, binding: binding)
        let question = try await core.hostAsk("  What period?  ", lease: lease)
        let status = try await core.status(taskID: id, connection: connection, peer: peer, headers: headers)
        try check(status.phase == .waitingForAnswer && status.question == question && question.text == "What period?", "question visible to owner")
        try await rejects(.missing) { _ = try await core.status(taskID: id, connection: other, peer: peer, headers: headers) }
        try await rejects(.missing) { _ = try await core.answer(taskID: id, questionID: question.id, requestID: UUID(), text: "x", connection: other, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.answer(taskID: id, questionID: UUID(), requestID: UUID(), text: "x", connection: connection, peer: peer, headers: headers) }
        let otherID = UUID()
        guard case .review(let otherReview) = try await core.stage(task: try parsedTask(otherID), binding: binding, peer: peer, headers: headers) else { throw Failure(label: "other task review") }
        _ = try await core.approveLocally(reviewID: otherReview.id, current: binding)
        let otherLease = try await core.hostBegin(taskID: otherID, binding: binding)
        _ = try await core.hostAsk("Other task?", lease: otherLease)
        try await rejects(.conflict) { _ = try await core.answer(taskID: otherID, questionID: question.id, requestID: UUID(), text: "wrong task", connection: connection, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "do not answer", connection: connection, peer: peer, headers: headers) }
        let answerID = UUID()
        let accepted = try await withThrowingTaskGroup(of: UUID.self, returning: [UUID].self) { group in
            for _ in 0..<8 { group.addTask { try await core.answer(taskID: id, questionID: question.id, requestID: answerID, text: "  last year ", connection: connection, peer: peer, headers: headers) } }
            var values: [UUID] = []; for try await value in group { values.append(value) }; return values
        }
        try check(accepted.count == 8 && accepted.allSatisfy { $0 == answerID }, "duplicate returns one receipt")
        try await rejects(.conflict) { _ = try await core.answer(taskID: id, questionID: question.id, requestID: answerID, text: "different", connection: connection, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.hostAsk("too early", lease: lease) }
        let taken = try await core.hostTakeAnswer(lease: lease)
        try check(taken?.requestID == answerID && taken?.text == "last year", "host consumes exact untrusted answer")
        try check(try await core.hostTakeAnswer(lease: lease) == nil, "answer consumed once")
        let second = try await core.hostAsk("Which format?", lease: lease)
        _ = try await core.answer(taskID: id, questionID: question.id, requestID: answerID, text: "last year", connection: connection, peer: peer, headers: headers)
        try check(try await core.status(taskID: id, connection: connection, peer: peer, headers: headers).question == second, "old retry does not answer new question")
        try await rejects(.conflict) { _ = try await core.answer(taskID: id, questionID: second.id, requestID: answerID, text: "last year", connection: connection, peer: peer, headers: headers) }
        let secondID = UUID()
        try await rejects(.unsupported) { _ = try await core.answer(taskID: id, questionID: second.id, requestID: secondID, text: String(repeating: "😀", count: 1001), connection: connection, peer: peer, headers: headers) }
        _ = try await core.answer(taskID: id, questionID: second.id, requestID: secondID, text: "ok", connection: connection, peer: peer, headers: headers)
        _ = try await core.hostTakeAnswer(lease: lease)
        try await core.hostRequireLocalApproval(lease: lease)
        try await rejects(.conflict) { _ = try await core.answer(taskID: id, questionID: second.id, requestID: UUID(), text: "I approve", connection: connection, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "approve", connection: connection, peer: peer, headers: headers) }
        try await core.hostResumeAfterLocalApproval(lease: lease)
        let steerID = UUID()
        _ = try await core.steer(taskID: id, requestID: steerID, text: "  shorter  ", connection: connection, peer: peer, headers: headers)
        try await rejects(.conflict) { try await core.hostFinish(lease: lease) }
        try await rejects(.unsupported) { _ = try await core.steer(taskID: id, requestID: UUID(), text: String(repeating: "😀", count: 2001), connection: connection, peer: peer, headers: headers) }
        _ = try await core.steer(taskID: id, requestID: steerID, text: "shorter", connection: connection, peer: peer, headers: headers)
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: steerID, text: "longer", connection: connection, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: answerID, text: "same ID", connection: connection, peer: peer, headers: headers) }
        let steer = try await core.hostTakeSteer(lease: lease)
        try check(steer?.requestID == steerID && steer?.text == "shorter", "steer queued once")
        try check(try await core.hostTakeSteer(lease: lease) == nil, "steer consumed once")
        for index in 0..<16 { _ = try await core.steer(taskID: id, requestID: UUID(), text: "steer \(index)", connection: connection, peer: peer, headers: headers) }
        try await rejects(.capacity) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "overflow", connection: connection, peer: peer, headers: headers) }
        try check(try await core.cancel(taskID: id, connection: connection, peer: peer, headers: headers), "inert task cancelled")
        try await rejects(.conflict) { _ = try await core.hostTakeSteer(lease: lease) }
        try await rejects(.conflict) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "after cancellation", connection: connection, peer: peer, headers: headers) }
        try await rejects(.conflict) { _ = try await core.hostAsk("late", lease: lease) }
    }
    static func receiptBounds() async throws {
        let (core, connection, binding, id) = try await setup()
        let lease = try await core.hostBegin(taskID: id, binding: binding)
        let firstSteer = UUID()
        for index in 0..<64 {
            let requestID = index == 0 ? firstSteer : UUID()
            _ = try await core.steer(taskID: id, requestID: requestID, text: "instruction \(index)", connection: connection, peer: peer, headers: headers)
            guard try await core.hostTakeSteer(lease: lease) != nil else { throw Failure(label: "missing steer") }
        }
        _ = try await core.steer(taskID: id, requestID: firstSteer, text: "instruction 0", connection: connection, peer: peer, headers: headers)
        try check(try await core.hostTakeSteer(lease: lease) == nil, "old steer receipt survives full ledger")
        try await rejects(.capacity) { _ = try await core.steer(taskID: id, requestID: UUID(), text: "overflow", connection: connection, peer: peer, headers: headers) }
        var firstQuestion: MCPInboundQuestion?; var firstAnswerID: UUID?
        for index in 0..<64 {
            let question = try await core.hostAsk("question \(index)", lease: lease)
            let requestID = UUID()
            if index == 0 { firstQuestion = question; firstAnswerID = requestID }
            _ = try await core.answer(taskID: id, questionID: question.id, requestID: requestID, text: "answer \(index)", connection: connection, peer: peer, headers: headers)
            guard try await core.hostTakeAnswer(lease: lease) != nil else { throw Failure(label: "missing answer") }
        }
        guard let firstQuestion, let firstAnswerID else { throw Failure(label: "first receipt") }
        let newQuestion = try await core.hostAsk("new question", lease: lease)
        _ = try await core.answer(taskID: id, questionID: firstQuestion.id, requestID: firstAnswerID, text: "answer 0", connection: connection, peer: peer, headers: headers)
        try check(try await core.status(taskID: id, connection: connection, peer: peer, headers: headers).question == newQuestion, "old answer receipt survives full ledger")
        try await rejects(.capacity) { _ = try await core.answer(taskID: id, questionID: newQuestion.id, requestID: UUID(), text: "overflow", connection: connection, peer: peer, headers: headers) }
        try check(try await core.cancel(taskID: id, connection: connection, peer: peer, headers: headers), "full ledger can still be cancelled")
    }
    static func waits() async throws {
        let clock = TestClock(), gate = SleepGate()
        let (core, connection, binding, id) = try await setup(clock: clock, sleep: { try await gate.sleep($0) })
        let changedWait = Task { try await core.wait(taskID: id, timeoutSeconds: 30, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 1)
        let lease = try await core.hostBegin(taskID: id, binding: binding)
        await gate.wakeAll()
        let changed = try await changedWait.value
        try check(changed.changed && changed.status.phase == .running, "wait observes actual phase change")
        let timeout = Task { try await core.wait(taskID: id, timeoutSeconds: 30, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 2); clock.set(31_000); await gate.wakeAll()
        let timed = try await timeout.value
        try check(!timed.changed && timed.status.phase == .running, "timeout does not cancel task")
        let cancelled = Task { try await core.wait(taskID: id, timeoutSeconds: 1, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 3); cancelled.cancel()
        do { _ = try await cancelled.value; throw Failure(label: "wait ignored cancellation") } catch is CancellationError { count += 1 }
        try check(try await core.status(taskID: id, connection: connection, peer: peer, headers: headers).phase == .running, "cancel wait keeps task")
        try await rejects(.unsupported) { _ = try await core.wait(taskID: id, timeoutSeconds: 51, connection: connection, peer: peer, headers: headers) }
        let finishing = Task { try await core.wait(taskID: id, timeoutSeconds: 5, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 4); try await core.hostFinish(lease: lease); await gate.wakeAll()
        let finishResult = try await finishing.value
        try check(finishResult.changed && finishResult.status.phase == .finished, "wait sees host-reported finished state")
        let alreadyFinished = try await core.wait(taskID: id, timeoutSeconds: 5, connection: connection, peer: peer, headers: headers)
        try check(!alreadyFinished.changed && alreadyFinished.status.phase == .finished, "finished wait returns immediately")
        try check(!(try await core.cancel(taskID: id, connection: connection, peer: peer, headers: headers)), "finished task is not cancelled")
        let nextTask = UUID()
        guard case .review(let nextReview) = try await core.stage(task: try parsedTask(nextTask), binding: binding, peer: peer, headers: headers) else { throw Failure(label: "next task review") }
        _ = try await core.approveLocally(reviewID: nextReview.id, current: binding)
        let disconnected = Task { try await core.wait(taskID: nextTask, timeoutSeconds: 5, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 5); await core.connectionDidClose(connection); await gate.wakeAll()
        do { _ = try await disconnected.value; throw Failure(label: "closed connection wait returned") }
        catch MCPInboundAccessError.invalidConnection { count += 1 }
        try await rejects(.conflict) { _ = try await core.hostAsk("late", lease: lease) }
    }
    static func waitRevocationAndExpiry() async throws {
        do {
            let clock = TestClock(), gate = SleepGate()
            let (core, connection, _, id) = try await setup(clock: clock, sleep: { try await gate.sleep($0) })
            let waiting = Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
            try await awaitSleeps(gate, 1); await core.setForegroundActive(false); await gate.wakeAll()
            do { _ = try await waiting.value; throw Failure(label: "background wait") }
            catch MCPInboundAccessError.disabled { count += 1 }
        }
        do {
            let clock = TestClock(), gate = SleepGate()
            let (core, connection, _, id) = try await setup(clock: clock, sleep: { try await gate.sleep($0) })
            let waiting = Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
            try await awaitSleeps(gate, 1); clock.set(301_000); await gate.wakeAll()
            do { _ = try await waiting.value; throw Failure(label: "expired wait") }
            catch MCPInboundAccessError.invalidConnection { count += 1 }
        }
        do {
            let (core, connection, _, id) = try await setup()
            let waiting = Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
            try await Task.sleep(nanoseconds: 10_000_000); waiting.cancel()
            do { _ = try await waiting.value; throw Failure(label: "default sleeper cancellation") }
            catch is CancellationError { count += 1 }
            try check(try await core.status(taskID: id, connection: connection, peer: peer, headers: headers).phase == .queued, "default wait cancellation preserves queued task")
        }
    }
    static func waitDoesNotClearRateLimits() async throws {
        let clock = TestClock(), gate = SleepGate()
        let (core, connection, _, id) = try await setup(clock: clock, sleep: { try await gate.sleep($0) })
        let waiting = Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 1)
        let bad = [MCPInboundHeader("Authorization", "Bearer " + String(repeating: "z", count: 43))]
        for _ in 0..<4 { try await rejects(.unauthorized) { try await core.check(connection: connection, peer: peer, headers: bad) } }
        await gate.wakeAll(); try await awaitSleeps(gate, 2)
        try await rejects(.unauthorized) { try await core.check(connection: connection, peer: peer, headers: bad) }
        await gate.wakeAll()
        do { _ = try await waiting.value; throw Failure(label: "wait ignored lockout") }
        catch MCPInboundAccessError.rateLimited { count += 1 }
        try await rejects(.rateLimited) { try await core.check(connection: connection, peer: peer, headers: headers) }
    }
    static func waiterCapacity() async throws {
        let gate = SleepGate(), clock = TestClock()
        let (core, connection, _, id) = try await setup(clock: clock, sleep: { try await gate.sleep($0) })
        var workers: [Task<MCPInboundWaitResult, Error>] = []
        for _ in 0..<16 { workers.append(Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }) }
        try await awaitSleeps(gate, 16)
        try await rejects(.capacity) { _ = try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
        for worker in workers { worker.cancel() }
        for worker in workers { do { _ = try await worker.value; throw Failure(label: "wait cancellation") } catch is CancellationError {} }
        let extra = Task { try await core.wait(taskID: id, connection: connection, peer: peer, headers: headers) }
        try await awaitSleeps(gate, 17); extra.cancel()
        do { _ = try await extra.value; throw Failure(label: "new wait cancellation") } catch is CancellationError { count += 1 }
    }
    static func formats() throws {
        let id = "01234567-89ab-cdef-0123-456789abcdef"
        func body(_ name: String, _ args: String) -> Data { Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"\(name)\",\"arguments\":\(args)}}".utf8) }
        let taskID = UUID(uuidString: id)!
        try check(try MCPInboundFormat.parse(body("mika_wait_task", "{\"task_id\":\"\(id)\"}")) == .waitTask(.number(1), taskID, 30), "default wait")
        try check(try MCPInboundFormat.parse(body("mika_wait_task", "{\"task_id\":\"\(id)\",\"timeout_s\":50}")) == .waitTask(.number(1), taskID, 50), "max wait")
        let answer = "{\"task_id\":\"\(id)\",\"question_id\":\"\(id)\",\"request_id\":\"\(id)\",\"text\":\" hello \"}"
        try check(try MCPInboundFormat.parse(body("mika_answer", answer)) == .answerTask(.number(1), taskID, taskID, taskID, "hello"), "answer format")
        let steer = "{\"task_id\":\"\(id)\",\"request_id\":\"\(id)\",\"text\":\"note\"}"
        try check(try MCPInboundFormat.parse(body("mika_steer_task", steer)) == .steerTask(.number(1), taskID, taskID, "note"), "steer format")
        let bad = [body("mika_wait_task", "{\"task_id\":\"\(id)\",\"timeout_s\":51}"), body("mika_answer", "{\"task_id\":\"\(id)\",\"text\":\"yes\"}"), body("mika_steer_task", "{\"task_id\":\"\(id)\",\"text\":\"yes\"}"), body("mika_wait_task", "{\"task_id\":\"\(id)\",\"timeout_s\":0}")]
        for input in bad {
            do { _ = try MCPInboundFormat.parse(input); throw Failure(label: "invalid format accepted") }
            catch MCPInboundFormatError.invalidParameters { count += 1 }
        }
    }
    static func main() async {
        do { try formats(); try await interactions(); try await receiptBounds(); try await waits(); try await waitRevocationAndExpiry(); try await waitDoesNotClearRateLimits(); try await waiterCapacity(); print("PASS interactions: \(count) checks; synthetic only") }
        catch { print("FAIL interactions: \(error)"); exit(1) }
    }
}
