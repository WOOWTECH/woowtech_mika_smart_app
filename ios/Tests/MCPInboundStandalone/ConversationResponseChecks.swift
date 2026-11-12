import Foundation

@main enum ConversationResponseChecks {
    struct Failure: Error { let label: String }
    static var count = 0
    static func check(_ value: Bool, _ label: String) throws { guard value else { throw Failure(label: label) }; count += 1 }
    static let token = String(repeating: "c", count: 43)
    static let peer = MCPInboundPeer(addressBytes: [127,0,0,1])!
    static let headers = [MCPInboundHeader("Authorization", "Bearer " + token)]
    static func task(_ goal: String, conversation: String? = nil, id: UUID? = nil) throws -> MCPInboundModelTask {
        var args: [String: String] = ["goal": goal]
        if let conversation { args["conversation"] = conversation }
        if let id { args["request_id"] = id.uuidString.lowercased() }
        let params: [String: Any] = ["name":"mika_run_task", "arguments":args]
        let root: [String: Any] = ["jsonrpc":"2.0", "id":1, "method":"tools/call", "params":params]
        guard case .runTask(_, let item) = try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: root)) else { throw Failure(label:"parse") }
        return item
    }
    static func rejects(_ expected: MCPInboundAccessError, _ work: () async throws -> Void) async throws {
        do { try await work(); throw Failure(label:"expected rejection") }
        catch let e as MCPInboundAccessError { try check(e == expected, "wrong error \(e)") }
    }
    static func review(_ core: MCPInboundAccessTasks, _ task: MCPInboundModelTask, _ binding: MCPInboundReviewBinding) async throws -> MCPInboundReview {
        guard case .review(let r) = try await core.stage(task: task, binding: binding, peer: peer, headers: headers) else { throw Failure(label:"review") }
        return r
    }
    static func envelope(_ payload: JSONValue, id: MCPInboundID = .number(4)) throws -> [String: Any] {
        let bytes = try MCPInboundResponses.success(id: id, payload: payload)
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String:Any],
              let result = root["result"] as? [String:Any], let content = result["content"] as? [[String:Any]],
              let text = content.first?["text"] as? String, let embedded = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary,
              let structured = result["structuredContent"] as? NSDictionary, embedded == structured else { throw Failure(label:"wire structured and content mismatch") }
        try check(root["jsonrpc"] as? String == "2.0" && result["isError"] as? Bool == false && content.first?["type"] as? String == "text", "response envelope")
        return structured as! [String:Any]
    }
    static func main() async {
        do {
            let initData = try MCPInboundResponses.initialize(id:.number(1),version:"2025-11-25",serverVersion:"test")
            let initRoot = try JSONSerialization.jsonObject(with:initData) as! [String:Any]
            let initResult = initRoot["result"] as! [String:Any]
            try check(initResult["protocolVersion"] as? String == "2025-11-25", "legacy initialization")
            let pingRoot = try JSONSerialization.jsonObject(with:MCPInboundResponses.ping(id:.number(2))) as! [String:Any]
            try check((pingRoot["result"] as? [String:Any])?.isEmpty == true, "ping")
            let listRoot = try JSONSerialization.jsonObject(with:MCPInboundResponses.tools(id:.number(3))) as! [String:Any]
            let tools = (listRoot["result"] as! [String:Any])["tools"] as! [[String:Any]]
            try check(tools.map { $0["name"] as! String } == ["mika_run_task","mika_task_status","mika_wait_task","mika_answer","mika_steer_task","mika_cancel_task","mika_list_tasks"], "seven task tools only")
            let schemas = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"] as! String, $0["inputSchema"] as! [String:Any]) })
            for name in ["mika_answer", "mika_steer_task"] {
                let schema = schemas[name]!
                try check(Set(schema["required"] as! [String]) == Set(["task_id","text"]) && Set((schema["properties"] as! [String:Any]).keys) == Set(["task_id","text"]) && schema["additionalProperties"] as? Bool == false, "Android answer and steer schema")
            }
            let required: [String: Set<String>] = [
                "mika_run_task": ["goal"], "mika_task_status": ["task_id"], "mika_wait_task": ["task_id"],
                "mika_answer": ["task_id", "text"], "mika_steer_task": ["task_id", "text"],
                "mika_cancel_task": ["task_id"], "mika_list_tasks": []
            ]
            for (name, expected) in required {
                let schema = schemas[name]!
                try check(Set(schema["required"] as! [String]) == expected && schema["additionalProperties"] as? Bool == false, "Android required fields: " + name)
            }
            let runSchema = schemas["mika_run_task"]!
            try check(runSchema["required"] as? [String] == ["goal"] && Set((runSchema["properties"] as! [String:Any]).keys) == Set(["goal","request_id","conversation"]), "run schema")
            let rpcError = try JSONSerialization.jsonObject(with:MCPInboundResponses.protocolError(id:.number(9),code:-32602,message:"Invalid params")) as! [String:Any]
            try check((rpcError["error"] as? [String:Any])?["code"] as? Int == -32602 && rpcError["result"] == nil, "protocol error")
            let core = MCPInboundAccessTasks(clock: { 1000 }, wallClock: { 1_700_000_000_123 })
            await core.setForegroundActive(true); try await core.enableByUser(scope:.loopback, token:Data(token.utf8))
            let c = try await core.open(peer:peer, headers:headers), other = try await core.open(peer:peer, headers:headers)
            let binding = MCPInboundReviewBinding(connection:c,destinationRevision:UUID(),contextRevision:UUID())
            let otherBinding = MCPInboundReviewBinding(connection:other,destinationRevision:binding.destinationRevision,contextRevision:binding.contextRevision)
            let r = try await review(core, try task("first"), binding)
            let first = try await core.approveLocally(reviewID:r.id,current:binding)
            let initial = try await core.snapshot(taskID:first.taskID,connection:c,peer:peer,headers:headers)
            try check(initial.conversation.hasPrefix("mcp-") && initial.startedAtMs == 1_700_000_000_123, "new id and wall clock")
            let initialJSON = try envelope(MCPInboundResponses.task(initial))
            try check(initialJSON["status"] as? String == "starting" && initialJSON["goal"] as? String == "first" && initialJSON["answerable"] as? Bool == false, "run response")
            try await rejects(.conflict) { _ = try await core.stage(task:try task("premature",conversation:initial.conversation),binding:binding,peer:peer,headers:headers) }
            let lease = try await core.hostBegin(taskID:first.taskID,binding:binding)
            try check(try await core.hostConversation(lease:lease).isEmpty, "initial empty context")
            try await core.hostFinish(lease:lease,answer:"first answer",contextIsExactlyOneTurn:true)
            let done = try await core.snapshot(taskID:first.taskID,connection:c,peer:peer,headers:headers)
            let doneJSON = try envelope(MCPInboundResponses.task(done,changed:true),id:.string("wait-1"))
            try check(doneJSON["status"] as? String == "done" && doneJSON["answer"] as? String == "first answer" && doneJSON["changed"] as? Bool == true, "done wait")
            try await rejects(.conflict) { _ = try await core.stage(task:try task("cross",conversation:initial.conversation),binding:otherBinding,peer:peer,headers:headers) }
            let changed = MCPInboundReviewBinding(connection:c,destinationRevision:UUID(),contextRevision:binding.contextRevision)
            try await rejects(.conflict) { _ = try await core.stage(task:try task("changed",conversation:initial.conversation),binding:changed,peer:peer,headers:headers) }
            let continuation = try task("second",conversation:"  " + initial.conversation + "  ",id:UUID())
            try check(continuation.conversation == initial.conversation, "Android trims conversation")
            try check(try task("blank",conversation:"  ").conversation == nil, "Android blank means new")
            let r2 = try await review(core,continuation,binding)
            try check(r2.task == continuation, "review contains exact continuation")
            let preview = try await core.reviewConversation(reviewID:r2.id,current:binding)
            try check(preview.count == 1 && preview[0].goal == "first" && preview[0].answer == "first answer", "review sees exact retained history")
            try await rejects(.invalidReview) { _ = try await core.reviewConversation(reviewID:UUID(),current:binding) }
            try await rejects(.invalidReview) { _ = try await core.reviewConversation(reviewID:r2.id,current:changed) }
            let second = try await core.approveLocally(reviewID:r2.id,current:binding)
            let secondSnapshot = try await core.snapshot(taskID:second.taskID,connection:c,peer:peer,headers:headers)
            try check(secondSnapshot.conversation == initial.conversation, "same conversation")
            let lease2 = try await core.hostBegin(taskID:second.taskID,binding:binding)
            let turns = try await core.hostConversation(lease:lease2)
            try check(turns.count == 1 && turns[0].goal == "first" && turns[0].answer == "first answer", "prior completed turn")
            let question = try await core.hostAsk("which?",lease:lease2)
            let asking = try await core.snapshot(taskID:second.taskID,connection:c,peer:peer,headers:headers)
            let askingJSON = try envelope(MCPInboundResponses.task(asking))
            try check(askingJSON["question"] as? String == "which?" && askingJSON["answerable"] as? Bool == true, "question response")
            _ = try await core.answer(taskID:second.taskID,questionID:question.id,text:"x",connection:c,peer:peer,headers:headers)
            _ = try await core.hostTakeAnswer(lease:lease2)
            let replyJSON = try envelope(MCPInboundResponses.answer(taskID:second.taskID))
            try check(replyJSON["accepted"] as? Bool == true && replyJSON["task_id"] as? String == second.taskID.uuidString.lowercased(), "answer response")
            let messageID = try await core.steer(taskID:second.taskID,text:"add",connection:c,peer:peer,headers:headers)
            let steerJSON = try envelope(MCPInboundResponses.steer(taskID:second.taskID,messageID:messageID))
            try check(steerJSON["message_id"] as? String == messageID.uuidString.lowercased(), "steer response")
            let running = try await core.snapshot(taskID:second.taskID,connection:c,peer:peer,headers:headers)
            let runningJSON = try envelope(MCPInboundResponses.task(running))
            try check((runningJSON["steers"] as? [[String:Any]])?.first?["state"] as? String == "received", "steer status")
            _ = try await core.hostTakeSteer(lease:lease2)
            try await core.hostFinish(lease:lease2,answer:"second answer")
            try await rejects(.conflict) { _ = try await core.stage(task:try task("incomplete",conversation:initial.conversation),binding:binding,peer:peer,headers:headers) }
            let listed = try await core.snapshots(limit:10,connection:c,peer:peer,headers:headers)
            let listJSON = try envelope(MCPInboundResponses.list(listed))
            try check((listJSON["tasks"] as? [[String:Any]])?.count == 2 && (listJSON["tasks"] as? [[String:Any]])?.first?["goal"] as? String == "second", "list newest")
            let cancelJSON = try envelope(MCPInboundResponses.cancel(taskID:second.taskID,cancelled:false,terminal:.finished))
            try check(cancelJSON["cancelled"] as? Bool == false && cancelJSON["status"] as? String == "done", "terminal cancel")
            let failure = try MCPInboundResponses.failure(id:.number(9),error:.conflict)
            let errorRoot = try JSONSerialization.jsonObject(with:failure) as! [String:Any]
            let errorResult = errorRoot["result"] as! [String:Any]
            try check(errorResult["isError"] as? Bool == true && errorResult["structuredContent"] == nil, "tool error envelope")
            try await rejects(.missing) { _ = try await core.snapshot(taskID:first.taskID,connection:other,peer:peer,headers:headers) }
            let localReview = try await review(core, try task("local action"), binding)
            let localTask = try await core.approveLocally(reviewID:localReview.id,current:binding)
            let localLease = try await core.hostBegin(taskID:localTask.taskID,binding:binding)
            try await core.hostRequireLocalApproval(lease:localLease)
            let localSnapshot = try await core.snapshot(taskID:localTask.taskID,connection:c,peer:peer,headers:headers)
            let localJSON = try envelope(MCPInboundResponses.task(localSnapshot))
            try check(localJSON["status"] as? String == "waiting_on_phone" && localJSON["answerable"] as? Bool == false, "local approval never answerable")
            try await rejects(.conflict) { _ = try await core.answer(taskID:localTask.taskID,text:"approve",connection:c,peer:peer,headers:headers) }
            try await core.hostResumeAfterLocalApproval(lease:localLease)
            try await core.hostFinish(lease:localLease,answer:"finished")
            try await rejects(.conflict) { _ = try await core.stage(task:try task("after approval",conversation:localSnapshot.conversation),binding:binding,peer:peer,headers:headers) }
            let cancelReview = try await review(core,try task("cancel"),binding)
            let cancelTask = try await core.approveLocally(reviewID:cancelReview.id,current:binding)
            let cancelSnapshot = try await core.snapshot(taskID:cancelTask.taskID,connection:c,peer:peer,headers:headers)
            _ = try await core.hostBegin(taskID:cancelTask.taskID,binding:binding)
            try check(try await core.cancel(taskID:cancelTask.taskID,connection:c,peer:peer,headers:headers), "cancel active")
            try await rejects(.conflict) { _ = try await core.stage(task:try task("after cancel",conversation:cancelSnapshot.conversation),binding:binding,peer:peer,headers:headers) }
            let boundedReview = try await review(core,try task("bounded"),binding)
            let boundedTask = try await core.approveLocally(reviewID:boundedReview.id,current:binding)
            let boundedLease = try await core.hostBegin(taskID:boundedTask.taskID,binding:binding)
            try await rejects(.capacity) { try await core.hostFinish(lease:boundedLease,answer:String(repeating:"x",count:32769)) }
            try check(try await core.hostConversation(lease:boundedLease).isEmpty, "oversize failure preserves state")
            try await core.hostFinish(lease:boundedLease,answer:"ok")
            let boundedSnapshot = try await core.snapshot(taskID:boundedTask.taskID,connection:c,peer:peer,headers:headers)
            try await rejects(.conflict) { _ = try await core.stage(task:try task("no proof",conversation:boundedSnapshot.conversation),binding:binding,peer:peer,headers:headers) }
            do { _ = try MCPInboundResponses.success(id:.number(1),payload:.object(["x":.string(String(repeating:"x",count:270_000))])); throw Failure(label:"oversize response accepted") }
            catch MCPInboundResponses.Error.tooLarge { count += 1 }
            await core.connectionDidClose(c)
            let replacement = try await core.open(peer:peer,headers:headers)
            let replacementBinding = MCPInboundReviewBinding(connection:replacement,destinationRevision:binding.destinationRevision,contextRevision:binding.contextRevision)
            try await rejects(.conflict) { _ = try await core.stage(task:try task("after close",conversation:initial.conversation),binding:replacementBinding,peer:peer,headers:headers) }
            let restarted = MCPInboundAccessTasks(clock: { 1000 })
            await restarted.setForegroundActive(true); try await restarted.enableByUser(scope:.loopback,token:Data(token.utf8))
            let restartConnection = try await restarted.open(peer:peer,headers:headers)
            let restartBinding = MCPInboundReviewBinding(connection:restartConnection,destinationRevision:binding.destinationRevision,contextRevision:binding.contextRevision)
            try await rejects(.conflict) { _ = try await restarted.stage(task:try task("after restart",conversation:initial.conversation),binding:restartBinding,peer:peer,headers:headers) }
            print("PASS conversation and response: \(count) checks; synthetic only")
        } catch { print("FAIL conversation and response: \(error)"); exit(1) }
    }
}
