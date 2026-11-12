// Regression adapted from the independent be5f7be review; expected outcomes inverted for the fixes.
import Foundation
final class Clock: @unchecked Sendable {
    private let lock=NSLock(); private var value:UInt64=1000
    func read()->UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v:UInt64) { lock.lock(); value=v; lock.unlock() }
}
@main enum IndependentInbound {
    struct Failure: Error { let label:String }
    static var count=0
    static func check(_ condition:Bool,_ label:String) throws { guard condition else { throw Failure(label:label) }; count += 1 }
    static let token=String(repeating:"a",count:43)
    static let good=[MCPInboundHeader("Authorization","Bearer "+token)]
    static let peer=MCPInboundPeer(addressBytes:[127,0,0,1])!
    static func makeTask(_ goal:String,id:UUID=UUID()) throws -> MCPInboundModelTask {
        let args:[String:String]=["goal":goal,"request_id":id.uuidString.lowercased()]
        let params:[String:Any]=["name":"mika_run_task","arguments":args]
        let raw:[String:Any]=["jsonrpc":"2.0","id":1,"method":"tools/call","params":params]
        guard case .runTask(_,let task)=try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject:raw)) else { throw Failure(label:"parse") }
        return task
    }
    static func active(_ clock:Clock) async throws -> MCPInboundAccessTasks {
        let gate=MCPInboundAccessTasks(clock:{clock.read()}); await gate.setForegroundActive(true)
        try await gate.enableByUser(scope:.loopback,token:Data(token.utf8));return gate
    }
    static func expiredCapacity() async throws {
        let clock=Clock(),gate=try await active(clock)
        var ids:[UUID]=[]
        for _ in 0..<32 { ids.append(try await gate.open(peer:peer,headers:good)) }
        clock.set(301_000)
        let firstNew=try await gate.open(peer:peer,headers:good)
        try await gate.check(connection:firstNew,peer:peer,headers:good)
        count += 1
        do { try await gate.check(connection:ids[0],peer:peer,headers:good);throw Failure(label:"expected expired connection") }
        catch MCPInboundAccessError.invalidConnection { count += 1 }
        let new=try await gate.open(peer:peer,headers:good);try await gate.check(connection:new,peer:peer,headers:good)
        try check(true,"cleanup one expired handle allows open")
        print("INBOUND_EXPIRED_CAPACITY expired=32 fresh_open=success no_old_check_required=1")
    }
    static func expiredPendingAndRecords() async throws {
        do {
            let clock=Clock(),gate=try await active(clock),old=try await gate.open(peer:peer,headers:good)
            let oldBinding=MCPInboundReviewBinding(connection:old,destinationRevision:UUID(),contextRevision:UUID())
            guard case .review = try await gate.stage(task:try makeTask("old pending"),binding:oldBinding,peer:peer,headers:good) else { throw Failure(label:"old pending") }
            clock.set(301_000)
            let new=try await gate.open(peer:peer,headers:good),newBinding=MCPInboundReviewBinding(connection:new,destinationRevision:UUID(),contextRevision:UUID()),task=try makeTask("new pending")
            guard case .review = try await gate.stage(task:task,binding:newBinding,peer:peer,headers:good) else { throw Failure(label:"expired pending blocks new review") }
            count += 1
            do { try await gate.check(connection:old,peer:peer,headers:good);throw Failure(label:"expected expiry") }
            catch MCPInboundAccessError.invalidConnection { count += 1 }
            guard case .review = try await gate.stage(task:task,binding:newBinding,peer:peer,headers:good) else { throw Failure(label:"new after cleanup") }
            count += 1
            print("INBOUND_EXPIRED_PENDING new_connection_busy=0 old_handle_check_not_required=1")
        }
        do {
            let clock=Clock(),gate=try await active(clock),old=try await gate.open(peer:peer,headers:good)
            let oldBinding=MCPInboundReviewBinding(connection:old,destinationRevision:UUID(),contextRevision:UUID())
            for i in 0..<50 {
                guard case .review(let r)=try await gate.stage(task:try makeTask("old record \(i)"),binding:oldBinding,peer:peer,headers:good) else { throw Failure(label:"record review") }
                _=try await gate.approveLocally(reviewID:r.id,current:oldBinding)
            }
            clock.set(301_000)
            let new=try await gate.open(peer:peer,headers:good),newBinding=MCPInboundReviewBinding(connection:new,destinationRevision:UUID(),contextRevision:UUID()),task=try makeTask("new record")
            guard case .review = try await gate.stage(task:task,binding:newBinding,peer:peer,headers:good) else { throw Failure(label:"expired records block new review") }
            count += 1
            do { try await gate.check(connection:old,peer:peer,headers:good);throw Failure(label:"expected expiry") }
            catch MCPInboundAccessError.invalidConnection { count += 1 }
            guard case .review = try await gate.stage(task:task,binding:newBinding,peer:peer,headers:good) else { throw Failure(label:"record after cleanup") }
            count += 1
            print("INBOUND_EXPIRED_RECORDS new_connection_capacity=0 old_handle_check_not_required=1")
        }
    }
    static func expireOnePreservesOther() async throws {
        let clock=Clock(), gate=try await active(clock)
        let old=try await gate.open(peer:peer,headers:good)
        let oldBinding=MCPInboundReviewBinding(connection:old,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review(let oldReview)=try await gate.stage(task:try makeTask("old"),binding:oldBinding,peer:peer,headers:good) else { throw Failure(label:"old review") }
        _=try await gate.approveLocally(reviewID:oldReview.id,current:oldBinding)
        clock.set(2_000)
        let fresh=try await gate.open(peer:peer,headers:good)
        let freshBinding=MCPInboundReviewBinding(connection:fresh,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review(let review)=try await gate.stage(task:try makeTask("fresh"),binding:freshBinding,peer:peer,headers:good) else { throw Failure(label:"fresh review") }
        clock.set(301_000)
        do { try await gate.check(connection:old,peer:peer,headers:good); throw Failure(label:"old connection still valid") }
        catch MCPInboundAccessError.invalidConnection { count += 1 }
        let status=try await gate.approveLocally(reviewID:review.id,current:freshBinding)
        try check(status.phase == .queued,"unexpired connection and review survive unrelated expiry")
    }
    static func oldReview() async throws {
        let clock=Clock(),gate=try await active(clock),id=try await gate.open(peer:peer,headers:good)
        let binding=MCPInboundReviewBinding(connection:id,destinationRevision:UUID(),contextRevision:UUID())
        let a=try makeTask("first"), b=try makeTask("second")
        guard case .review(let old)=try await gate.stage(task:a,binding:binding,peer:peer,headers:good) else { throw Failure(label:"old stage") }
        await gate.discardReview()
        guard case .review(let fresh)=try await gate.stage(task:b,binding:binding,peer:peer,headers:good) else { throw Failure(label:"fresh stage") }
        do { _=try await gate.approveLocally(reviewID:old.id,current:binding);throw Failure(label:"old accepted") }
        catch MCPInboundAccessError.invalidReview { count += 1 }
        let result=try await gate.approveLocally(reviewID:fresh.id,current:binding)
        count += 1
        try check(result.taskID==b.requestID && result.phase == .queued,"fresh review after stale attempt")
        print("INBOUND_STALE_REVIEW old_rejected=1 newer_review_cleared=0 restage_required=0")
    }
    static func replayLifecycle() async throws {
        let clock=Clock(),gate=try await active(clock),id=try await gate.open(peer:peer,headers:good)
        let binding=MCPInboundReviewBinding(connection:id,destinationRevision:UUID(),contextRevision:UUID())
        let task=try makeTask("review synthetic work")
        guard case .review(let review)=try await gate.stage(task:task,binding:binding,peer:peer,headers:good) else { throw Failure(label:"stage") }
        let same=try await gate.stage(task:task,binding:binding,peer:peer,headers:good)
        try check(same == .review(review),"pending retry same review")
        let status=try await gate.approveLocally(reviewID:review.id,current:binding)
        let duplicate=try await gate.stage(task:task,binding:binding,peer:peer,headers:good)
        try check(duplicate == .existing(status),"same connection retry existing")
        let changed=try makeTask("other synthetic work",id:task.requestID!)
        do { _=try await gate.stage(task:changed,binding:binding,peer:peer,headers:good);throw Failure(label:"conflicting id accepted") }
        catch MCPInboundAccessError.conflict { count += 1 }
        await gate.connectionDidClose(id)
        let next=try await gate.open(peer:peer,headers:good)
        let newBinding=MCPInboundReviewBinding(connection:next,destinationRevision:binding.destinationRevision,contextRevision:binding.contextRevision)
        guard case .review(let newReview)=try await gate.stage(task:task,binding:newBinding,peer:peer,headers:good) else { throw Failure(label:"fresh connection must review") }
        try check(newReview.id != review.id,"new connection needs new local review")
        await gate.setForegroundActive(false);await gate.setForegroundActive(true)
        do { _=try await gate.approveLocally(reviewID:newReview.id,current:newBinding);throw Failure(label:"background accepted") }
        catch MCPInboundAccessError.invalidReview { count += 1 }
        try await gate.enableByUser(scope:.loopback,token:Data(token.utf8))
        let rotated=try await gate.open(peer:peer,headers:good)
        let rotationBinding=MCPInboundReviewBinding(connection:rotated,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review(let pending)=try await gate.stage(task:task,binding:rotationBinding,peer:peer,headers:good) else { throw Failure(label:"rotation stage") }
        try await gate.enableByUser(scope:.loopback,token:Data(String(repeating:"b",count:43).utf8))
        do { _=try await gate.approveLocally(reviewID:pending.id,current:rotationBinding);throw Failure(label:"rotation accepted") }
        catch MCPInboundAccessError.invalidReview { count += 1 }
        print("INBOUND_REPLAY same_connection_existing=1 close_requires_review=1 background_and_token_invalidate=1")
    }
    static func queuedRotationAndBackground() async throws {
        let clock=Clock(),gate=try await active(clock),old=try await gate.open(peer:peer,headers:good),task=try makeTask("queued synthetic task")
        let binding=MCPInboundReviewBinding(connection:old,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review(let r)=try await gate.stage(task:task,binding:binding,peer:peer,headers:good) else { throw Failure(label:"queued before rotation") }
        _=try await gate.approveLocally(reviewID:r.id,current:binding)
        let token2=String(repeating:"b",count:43),headers2=[MCPInboundHeader("Authorization","Bearer "+token2)]
        try await gate.enableByUser(scope:.loopback,token:Data(token2.utf8))
        do { _=try await gate.status(taskID:task.requestID!,connection:old,peer:peer,headers:headers2);throw Failure(label:"old status survives rotation") }
        catch MCPInboundAccessError.invalidConnection { count += 1 }
        let next=try await gate.open(peer:peer,headers:headers2),nextBinding=MCPInboundReviewBinding(connection:next,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review(let nextReview)=try await gate.stage(task:task,binding:nextBinding,peer:peer,headers:headers2) else { throw Failure(label:"new token requires fresh review") }
        _=try await gate.approveLocally(reviewID:nextReview.id,current:nextBinding)
        await gate.setForegroundActive(false);await gate.setForegroundActive(true)
        try await gate.enableByUser(scope:.loopback,token:Data(token2.utf8))
        let third=try await gate.open(peer:peer,headers:headers2),thirdBinding=MCPInboundReviewBinding(connection:third,destinationRevision:UUID(),contextRevision:UUID())
        guard case .review = try await gate.stage(task:task,binding:thirdBinding,peer:peer,headers:headers2) else { throw Failure(label:"foreground requires fresh review") }
        count += 2
        print("INBOUND_QUEUED_REVOCATION rotation_and_background_remove_records=1 fresh_review_required=1")
    }
    static func malformedAndCloseRaces() async throws {
        let clock=Clock(),gate=try await active(clock),conn=try await gate.open(peer:peer,headers:good)
        let binding=MCPInboundReviewBinding(connection:conn,destinationRevision:UUID(),contextRevision:UUID()), task=try makeTask("valid review")
        guard case .review(let review)=try await gate.stage(task:task,binding:binding,peer:peer,headers:good) else { throw Failure(label:"valid review") }
        let badJSON=Data(#"{"jsonrpc":"2.0","id":1,"method":"ping","method":"tools/list"}"#.utf8)
        do { _=try MCPInboundFormat.parse(badJSON);throw Failure(label:"duplicate key accepted") }
        catch MCPInboundFormatError.malformed { count += 1 }
        do { try await gate.check(connection:conn,peer:peer,headers:[.init("Authorization","Bearer bad")]);throw Failure(label:"bad token accepted") }
        catch MCPInboundAccessError.unauthorized { count += 1 }
        let approved=try await gate.approveLocally(reviewID:review.id,current:binding)
        try check(approved.taskID == task.requestID,"invalid requests do not authorize or replace pending review")
        await gate.connectionDidClose(conn)
        var approvedBeforeClose=0
        for i in 0..<24 {
            let id=try await gate.open(peer:peer,headers:good)
            let b=MCPInboundReviewBinding(connection:id,destinationRevision:UUID(),contextRevision:UUID()),item=try makeTask("race \(i)")
            guard case .review(let pending)=try await gate.stage(task:item,binding:b,peer:peer,headers:good) else { throw Failure(label:"race stage") }
            let granted=await withTaskGroup(of:Bool.self,returning:Bool.self) { group in
                group.addTask { (try? await gate.approveLocally(reviewID:pending.id,current:b)) != nil }
                group.addTask { await gate.connectionDidClose(id); return false }
                var wasGranted=false
                for await value in group { wasGranted = wasGranted || value }
                return wasGranted
            }
            if granted { approvedBeforeClose += 1 }
            do { _=try await gate.status(taskID:item.requestID!,connection:id,peer:peer,headers:good);throw Failure(label:"closed status allowed") }
            catch MCPInboundAccessError.invalidConnection { count += 1 }
            let next=try await gate.open(peer:peer,headers:good),nb=MCPInboundReviewBinding(connection:next,destinationRevision:UUID(),contextRevision:UUID())
            guard case .review = try await gate.stage(task:item,binding:nb,peer:peer,headers:good) else { throw Failure(label:"closed queued record survived") }
            await gate.connectionDidClose(next)
        }
        print("INBOUND_CLOSE_RACE trials=24 locally_approved_before_close=\(approvedBeforeClose) closed_records_survived=0 malformed_did_not_authorize=1")
    }
    static func main() async {
        do { try await expiredCapacity(); try await expiredPendingAndRecords(); try await expireOnePreservesOther(); try await oldReview(); try await replayLifecycle(); try await queuedRotationAndBackground(); try await malformedAndCloseRaces(); print("INBOUND_INDEPENDENT_PASS checks=\(count) synthetic_only=1") }
        catch { print("INBOUND_INDEPENDENT_FAILURE \(error)");exit(1) }
    }
}
