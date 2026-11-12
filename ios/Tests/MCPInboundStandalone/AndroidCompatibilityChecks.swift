import Foundation

@main enum AndroidCompatibilityChecks {
    struct Failure: Error { let label: String }
    static var count = 0
    static func check(_ ok: Bool, _ label: String) throws {
        guard ok else { throw Failure(label: label) }; count += 1
    }
    static func parse(_ name: String, _ args: [String: Any]) throws -> MCPInboundRequest {
        let params: [String: Any] = ["name":name, "arguments":args]
        let root: [String: Any] = ["jsonrpc":"2.0", "id":1, "method":"tools/call", "params":params]
        return try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: root))
    }
    static func rejects(_ work: () async throws -> Void) async throws {
        do { try await work(); throw Failure(label: "expected rejection") }
        catch is MCPInboundAccessError { count += 1 }
    }
    static let token = String(repeating: "a", count: 43)
    static let headers = [MCPInboundHeader("Authorization", "Bearer " + token)]
    static let peer = MCPInboundPeer(addressBytes: [127,0,0,1])!
    static func main() async {
        do {
            guard case .runTask(.number(1), let task) = try parse("mika_run_task", ["goal":" work "]) else { throw Failure(label:"run") }
            try check(task.goal == "work" && task.requestID == nil, "run without id")
            try check(try parse("mika_task_status", ["task_id":" t1 "]) == .taskStatus(.number(1), "t1"), "status opaque id")
            try check(try parse("mika_cancel_task", ["task_id":"t1"]) == .cancelTask(.number(1), "t1"), "cancel")
            try check(try parse("mika_wait_task", ["task_id":"t1"]) == .waitTask(.number(1), "t1", 30), "wait default")
            try check(try parse("mika_list_tasks", [:]) == .listTasks(.number(1), 10), "list default")
            try check(try parse("mika_answer", ["task_id":"t1", "text":" yes "]) == .answerTask(.number(1), "t1", nil, nil, "yes"), "legacy answer")
            try check(try parse("mika_steer_task", ["task_id":"t1", "text":" more "]) == .steerTask(.number(1), "t1", nil, "more"), "legacy steer")
            for (name,args) in [("mika_answer",["task_id":"t1"]), ("mika_steer_task",["task_id":"t1", "text":"x", "request_id":"bad"]), ("mika_wait_task",["task_id":"t1", "timeout_s":51]), ("mika_phone_control",[:])] as [(String,[String:Any])] {
                do { _ = try parse(name,args); throw Failure(label:"bad schema accepted") }
                catch is MCPInboundFormatError { count += 1 }
            }
            let core = MCPInboundAccessTasks(clock: { 1000 })
            await core.setForegroundActive(true)
            try await core.enableByUser(scope: .loopback, token: Data(token.utf8))
            let connection = try await core.open(peer: peer, headers: headers)
            let binding = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID())
            guard case .review(let review) = try await core.stage(task: task, binding: binding, peer: peer, headers: headers) else { throw Failure(label:"review") }
            try await rejects { _ = try await core.stage(task: task, binding: binding, peer: peer, headers: headers) }
            let first = try await core.approveLocally(reviewID: review.id, current: binding)
            guard case .review(let next) = try await core.stage(task: task, binding: binding, peer: peer, headers: headers) else { throw Failure(label:"second review") }
            let second = try await core.approveLocally(reviewID: next.id, current: binding)
            try check(first.taskID != second.taskID, "idless run creates distinct tasks after local approval")
            let lease = try await core.hostBegin(taskID: first.taskID, binding: binding)
            let steerA = try await core.steer(taskID: first.taskID, text:"same", connection: connection, peer: peer, headers: headers)
            let steerB = try await core.steer(taskID: first.taskID, text:"same", connection: connection, peer: peer, headers: headers)
            try check(steerA != steerB, "idless steer retry is new")
            try check(try await core.hostTakeSteer(lease: lease)?.requestID == steerA, "first steer delivered")
            try check(try await core.hostTakeSteer(lease: lease)?.requestID == steerB, "second steer delivered")
            _ = try await core.hostAsk("first?", lease: lease)
            let answerA = try await core.answer(taskID: first.taskID, text:"same", connection: connection, peer: peer, headers: headers)
            try await rejects { _ = try await core.answer(taskID: first.taskID, text:"same", connection: connection, peer: peer, headers: headers) }
            try check(try await core.hostTakeAnswer(lease: lease)?.requestID == answerA, "first answer")
            _ = try await core.hostAsk("second?", lease: lease)
            let answerB = try await core.answer(taskID: first.taskID, text:"same", connection: connection, peer: peer, headers: headers)
            try check(answerA != answerB, "idless retry cannot be distinguished from next answer")
            _ = try await core.hostTakeAnswer(lease: lease)
            try await core.hostRequireLocalApproval(lease: lease)
            try await rejects { _ = try await core.answer(taskID: first.taskID, text:"approve", connection: connection, peer: peer, headers: headers) }
            try await rejects { _ = try await core.steer(taskID: first.taskID, text:"approve", connection: connection, peer: peer, headers: headers) }
            print("PASS Android compatibility: \(count) checks; synthetic only")
        } catch { print("FAIL Android compatibility: \(error)"); exit(1) }
    }
}
