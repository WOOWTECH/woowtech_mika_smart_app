import Foundation

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 1_000
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return time }
    func set(_ value: UInt64) { lock.lock(); defer { lock.unlock() }; time = value }
}
@main enum AccessTaskChecks {
    static var count = 0
    struct Failure: Error { let label: String }
    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw Failure(label: label) }; count += 1
    }
    static func rejects(_ expected: MCPInboundAccessError, _ operation: () async throws -> Void) async throws {
        do { try await operation(); throw Failure(label: "accepted \(expected)") }
        catch let error as MCPInboundAccessError { try check(error == expected, "incorrect rejection") }
    }
    static let token = String(repeating: "a", count: 43)
    static let good = [MCPInboundHeader("Authorization", "Bearer " + token)]
    static let bad = [MCPInboundHeader("authorization", "Bearer " + String(repeating: "b", count: 43))]
    static func peer(_ bytes: [UInt8]) -> MCPInboundPeer { MCPInboundPeer(addressBytes: bytes)! }
    static func task(_ text: String, id: UUID? = UUID(), conversation: String? = nil) throws -> MCPInboundModelTask {
        var args: [String: String] = ["goal": text]
        if let id { args["request_id"] = id.uuidString.lowercased() }
        if let conversation { args["conversation"] = conversation }
        let params: [String: Any] = ["name":"mika_run_task", "arguments":args]
        let json: [String: Any] = ["jsonrpc":"2.0", "id":1, "method":"tools/call", "params":params]
        guard case .runTask(_, let result) = try MCPInboundFormat.parse(JSONSerialization.data(withJSONObject: json)) else { throw Failure(label: "parse task") }
        return result
    }
    static func lifecycle() async throws {
            let clock = FakeClock(), gate = MCPInboundAccessTasks(clock: { clock.read() })
            let local = peer([127,0,0,1]), lan = peer([192,168,1,8]), publicIP = peer([8,8,8,8])
            try check(MCPInboundPeer(addressBytes: [1,2,3]) == nil, "invalid address")
            try await rejects(.disabled) { _ = try await gate.open(peer: local, headers: good) }
            try await rejects(.disabled) { try await gate.enableByUser(scope: .loopback, token: Data(token.utf8)) }
            await gate.setForegroundActive(true)
            do { try await gate.enableByUser(scope: .loopback, token: Data("short".utf8)); throw Failure(label: "token length") }
            catch MCPInboundAccessError.invalidToken { count += 1 }
            try await gate.enableByUser(scope: .loopback, token: Data(token.utf8))
            try await rejects(.sourceRejected) { _ = try await gate.open(peer: lan, headers: good) }
            try await rejects(.sourceRejected) { _ = try await gate.open(peer: publicIP, headers: good) }
            try await rejects(.browserRejected) { _ = try await gate.open(peer: local, headers: good + [.init("OrIgIn", "null")]) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: good + [.init("aUtHoRiZaTiOn", "Bearer " + token)]) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: good + [.init("Host ", "test")]) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: good + [.init("X", "a\r\nb")]) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: good + [.init("X", "a\u{01}b")]) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: Array(repeating: .init("x", "a"), count: 33)) }
            try await rejects(.malformedHeaders) { _ = try await gate.open(peer: local, headers: good + [.init("x", String(repeating: "a", count: 8193))]) }
            let v6Mapped = peer(Array(repeating: 0, count: 10) + [255,255,127,0,0,1])
            try check(local == v6Mapped, "IPv4 mapped identity")
            let connection = try await gate.open(peer: local, headers: good)
            try await gate.check(connection: connection, peer: v6Mapped, headers: good)
            try check(true, "authorized loopback")
            try await rejects(.unauthorized) { try await gate.check(connection: connection, peer: local, headers: []) }
            try await rejects(.invalidConnection) { try await gate.check(connection: UUID(), peer: local, headers: good) }
            let other = try await gate.open(peer: local, headers: good)
            let binding = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID())
            let different = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: binding.contextRevision)
            let first = try task("write a summary")
            guard case .review = try await gate.stage(task: try task("missing id", id: nil), binding: binding, peer: local, headers: good) else { throw Failure(label: "missing id review") }
            await gate.discardReview()
            try check(true, "missing id accepted with review")
            try await rejects(.unsupported) { _ = try await gate.stage(task: try task("old chat", conversation: "mcp-01234567-89ab-cdef-0123-456789abcdef"), binding: binding, peer: local, headers: good) }
            guard case .review(let review) = try await gate.stage(task: first, binding: binding, peer: local, headers: good) else { throw Failure(label: "review") }
            try check(review.task == first && review.binding == binding, "review exact snapshot")
            try check(try await gate.stage(task: first, binding: binding, peer: local, headers: good) == .review(review), "retry same review")
            try await rejects(.busy) { _ = try await gate.stage(task: try task("different"), binding: binding, peer: local, headers: good) }
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: review.id, current: different) }
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: review.id, current: binding) }
            guard case .review(let review2) = try await gate.stage(task: first, binding: binding, peer: local, headers: good) else { throw Failure(label: "review2") }
            let status = try await gate.approveLocally(reviewID: review2.id, current: binding)
            try check(status.taskID == first.requestID && status.phase == .queued, "local approval queues only")
            try check(try await gate.stage(task: first, binding: binding, peer: local, headers: good) == .existing(status), "idempotent same connection retry")
            try await rejects(.conflict) { _ = try await gate.stage(task: try task("different text", id: first.requestID), binding: binding, peer: local, headers: good) }
            let otherBinding = MCPInboundReviewBinding(connection: other, destinationRevision: binding.destinationRevision, contextRevision: binding.contextRevision)
            try await rejects(.conflict) { _ = try await gate.stage(task: first, binding: otherBinding, peer: local, headers: good) }
            try await rejects(.missing) { _ = try await gate.status(taskID: status.taskID, connection: other, peer: local, headers: good) }
            try check(try await gate.list(limit: 10, connection: other, peer: local, headers: good).isEmpty, "other connection list isolated")
            try check(try await gate.list(limit: 1, connection: connection, peer: local, headers: good) == [status], "own list")
            try await rejects(.unsupported) { _ = try await gate.list(limit: 51, connection: connection, peer: local, headers: good) }
            try check(try await gate.cancel(taskID: status.taskID, connection: connection, peer: local, headers: good), "cancel queued")
            try check(!(try await gate.cancel(taskID: status.taskID, connection: connection, peer: local, headers: good)), "cancel terminal is no-op")
            try check(try await gate.status(taskID: status.taskID, connection: connection, peer: local, headers: good).phase == .cancelled, "cancelled status")
            try check(try await gate.stage(task: first, binding: binding, peer: local, headers: good) == .existing(.init(taskID: status.taskID, phase: .cancelled)), "retry does not restart")
            guard case .review(let closeReview) = try await gate.stage(task: try task("pending"), binding: binding, peer: local, headers: good) else { throw Failure(label: "close review") }
            await gate.connectionDidClose(connection)
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: closeReview.id, current: binding) }
            try await rejects(.invalidConnection) { _ = try await gate.status(taskID: status.taskID, connection: connection, peer: local, headers: good) }
            await gate.setForegroundActive(false); await gate.setForegroundActive(true)
            try await rejects(.disabled) { _ = try await gate.open(peer: local, headers: good) }
    }
    static func network() async throws {
            let clock = FakeClock(), gate = MCPInboundAccessTasks(clock: { clock.read() })
            let local = peer([127,0,0,1]), lan = peer([192,168,1,8])
            await gate.setForegroundActive(true)
            try await gate.enableByUser(scope: .privateNetworks, token: Data(token.utf8))
            for allowed in [[10,0,0,1], [172,16,0,1], [172,31,0,1], [192,168,0,1], [100,64,0,1], [100,127,0,1], [169,254,0,1], [127,0,0,1]] as [[UInt8]] {
                let id = try await gate.open(peer: peer(allowed), headers: good); await gate.connectionDidClose(id); count += 1
            }
            for denied in [[172,15,0,1], [172,32,0,1], [100,63,0,1], [100,128,0,1], [8,8,8,8], [0,0,0,0]] as [[UInt8]] {
                try await rejects(.sourceRejected) { _ = try await gate.open(peer: peer(denied), headers: good) }
            }
            let v6local: [UInt8] = [0xfc] + Array(repeating: UInt8(0), count: 14) + [1]
            let v6link: [UInt8] = [0xfe, 0x80] + Array(repeating: UInt8(0), count: 13) + [1]
            let v6loop: [UInt8] = Array(repeating: UInt8(0), count: 15) + [1]
            for bytes in [v6local, v6link, v6loop] {
                let id = try await gate.open(peer: peer(bytes), headers: good); await gate.connectionDidClose(id); count += 1
            }
            try await rejects(.sourceRejected) { _ = try await gate.open(peer: peer([0x20,1] + Array(repeating: 0, count: 14)), headers: good) }
            for _ in 0..<5 { try await rejects(.unauthorized) { _ = try await gate.open(peer: lan, headers: bad) } }
            try await rejects(.rateLimited) { _ = try await gate.open(peer: lan, headers: good) }
            let independent = try await gate.open(peer: local, headers: good); await gate.connectionDidClose(independent)
            try check(true, "rate limit is per peer")
            clock.set(61_001)
            let afterCooldown = try await gate.open(peer: lan, headers: good)
            try check(true, "cooldown expires")
            clock.set(361_001)
            try await rejects(.invalidConnection) { try await gate.check(connection: afterCooldown, peer: lan, headers: good) }
            let renewed = try await gate.open(peer: lan, headers: good)
            let renewBinding = MCPInboundReviewBinding(connection: renewed, destinationRevision: UUID(), contextRevision: UUID())
            guard case .review(let expiryReview) = try await gate.stage(task: try task("expire"), binding: renewBinding, peer: lan, headers: good) else { throw Failure(label: "expire") }
            clock.set(661_001)
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: expiryReview.id, current: renewBinding) }
            let beforeRotation = try await gate.open(peer: lan, headers: good)
            let rotationBinding = MCPInboundReviewBinding(connection: beforeRotation, destinationRevision: UUID(), contextRevision: UUID())
            guard case .review(let rotationReview) = try await gate.stage(task: try task("rotation"), binding: rotationBinding, peer: lan, headers: good) else { throw Failure(label: "rotation review") }
            try await gate.enableByUser(scope: .privateNetworks, token: Data(String(repeating:"z", count:43).utf8))
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: rotationReview.id, current: rotationBinding) }
            let newHeaders = [MCPInboundHeader("Authorization", "Bearer " + String(repeating:"z", count:43))]
            try await rejects(.invalidConnection) { try await gate.check(connection: beforeRotation, peer: lan, headers: newHeaders) }
            try await rejects(.unauthorized) { _ = try await gate.open(peer: lan, headers: good) }
            let rotated = try await gate.open(peer: lan, headers: newHeaders)
            try check(true, "rotation requires new connection and token")
            let disabledBinding = MCPInboundReviewBinding(connection: rotated, destinationRevision: UUID(), contextRevision: UUID())
            guard case .review(let disabledReview) = try await gate.stage(task: try task("disable"), binding: disabledBinding, peer: lan, headers: newHeaders) else { throw Failure(label: "disable review") }
            await gate.disableByUser()
            try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: disabledReview.id, current: disabledBinding) }
            try await rejects(.disabled) { try await gate.check(connection: rotated, peer: lan, headers: newHeaders) }
            try await gate.enableByUser(scope: .privateNetworks, token: Data(String(repeating:"z", count:43).utf8))
            try await rejects(.invalidConnection) { try await gate.check(connection: rotated, peer: lan, headers: newHeaders) }
            let fresh = try await gate.open(peer: lan, headers: newHeaders)
            clock.set(1)
            try await rejects(.clockFailure) { try await gate.check(connection: fresh, peer: lan, headers: newHeaders) }
            try await rejects(.disabled) { _ = try await gate.open(peer: lan, headers: newHeaders) }
    }
    static func concurrencyAndLimits() async throws {
        let clock = FakeClock(), gate = MCPInboundAccessTasks(clock: { clock.read() })
        let local = peer([127,0,0,1])
        await gate.setForegroundActive(true)
        try await gate.enableByUser(scope: .privateNetworks, token: Data(token.utf8))
        let connection = try await gate.open(peer: local, headers: good)
        let binding = MCPInboundReviewBinding(connection: connection, destinationRevision: UUID(), contextRevision: UUID())
        let item = try task("concurrent")
        guard case .review(let review) = try await gate.stage(task: item, binding: binding, peer: local, headers: good) else { throw Failure(label: "concurrent review") }
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<8 { group.addTask { (try? await gate.approveLocally(reviewID: review.id, current: binding)) != nil } }
            var result = 0
            for await success in group { if success { result += 1 } }
            return result
        }
        try check(successes == 1, "concurrent approvals create only one queued record")
        try check(try await gate.list(limit: 10, connection: connection, peer: local, headers: good).count == 1, "one record after racing approvals")
        guard case .review(let throttledReview) = try await gate.stage(task: try task("throttle"), binding: binding, peer: local, headers: good) else { throw Failure(label: "throttle review") }
        for _ in 0..<5 { try await rejects(.unauthorized) { try await gate.check(connection: connection, peer: local, headers: bad) } }
        try await rejects(.invalidReview) { _ = try await gate.approveLocally(reviewID: throttledReview.id, current: binding) }
        try await rejects(.rateLimited) { try await gate.check(connection: connection, peer: local, headers: good) }
        clock.set(61_001)
        try await gate.check(connection: connection, peer: local, headers: good)
        let otherPeer = peer([10,0,0,1])
        try await rejects(.invalidConnection) { try await gate.check(connection: connection, peer: otherPeer, headers: good) }
        let mapped = peer(Array(repeating: UInt8(0), count: 10) + [255,255,127,0,0,1])
        for _ in 0..<4 { try await rejects(.unauthorized) { _ = try await gate.open(peer: local, headers: bad) } }
        try await rejects(.unauthorized) { _ = try await gate.open(peer: mapped, headers: bad) }
        try await rejects(.rateLimited) { _ = try await gate.open(peer: local, headers: good) }

        let capacityClock = FakeClock(), bounded = MCPInboundAccessTasks(clock: { capacityClock.read() })
        await bounded.setForegroundActive(true)
        try await bounded.enableByUser(scope: .privateNetworks, token: Data(token.utf8))
        for value in 0..<256 {
            let remote = peer([10, 1, UInt8(value), 1])
            do { _ = try await bounded.open(peer: remote, headers: bad); throw Failure(label: "bad token accepted") }
            catch MCPInboundAccessError.unauthorized { }
        }
        try check(true, "256 synthetic failures recorded")
        let overflow = peer([10,2,0,1])
        try await rejects(.capacity) { _ = try await bounded.open(peer: overflow, headers: good) }
        capacityClock.set(61_001)
        let reopened = try await bounded.open(peer: overflow, headers: good)
        await bounded.connectionDidClose(reopened)
        try check(true, "expired failure entries release capacity")
        var connections: [UUID] = []
        for _ in 0..<32 { connections.append(try await bounded.open(peer: overflow, headers: good)) }
        try await rejects(.capacity) { _ = try await bounded.open(peer: overflow, headers: good) }
        await bounded.connectionDidClose(connections[0])
        _ = try await bounded.open(peer: overflow, headers: good)
        try check(true, "connection close releases bounded capacity")
        try await rejects(.invalidToken) { try await bounded.enableByUser(scope: .privateNetworks, token: Data("short".utf8)) }
        try await rejects(.disabled) { try await bounded.check(connection: connections[1], peer: overflow, headers: good) }

        let tasks = MCPInboundAccessTasks(clock: { capacityClock.read() })
        await tasks.setForegroundActive(true)
        try await tasks.enableByUser(scope: .loopback, token: Data(token.utf8))
        let taskConnection = try await tasks.open(peer: local, headers: good)
        let taskBinding = MCPInboundReviewBinding(connection: taskConnection, destinationRevision: UUID(), contextRevision: UUID())
        for index in 0..<50 {
            guard case .review(let review) = try await tasks.stage(task: try task("queued \(index)"), binding: taskBinding, peer: local, headers: good) else { throw Failure(label: "capacity review") }
            _ = try await tasks.approveLocally(reviewID: review.id, current: taskBinding)
        }
        try check(try await tasks.list(limit: 50, connection: taskConnection, peer: local, headers: good).count == 50, "task records bounded to fifty")
        try await rejects(.capacity) { _ = try await tasks.stage(task: try task("overflow"), binding: taskBinding, peer: local, headers: good) }
    }
    static func format() throws {
            let json = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_task_status","arguments":{"task_id":"01234567-89ab-cdef-0123-456789abcdef"}}}"#
            guard case .taskStatus(.number(1), _) = try MCPInboundFormat.parse(Data(json.utf8)) else { throw Failure(label: "status format") }
            let cancel = json.replacingOccurrences(of: "mika_task_status", with: "mika_cancel_task")
            guard case .cancelTask(.number(1), _) = try MCPInboundFormat.parse(Data(cancel.utf8)) else { throw Failure(label: "cancel format") }
            let list = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"mika_list_tasks","arguments":{"limit":50}}}"#
            try check(try MCPInboundFormat.parse(Data(list.utf8)) == .listTasks(.number(1), 50), "list format")
            for limit in ["0", "51", "1.5", "true", "\"1\""] {
                do { _ = try MCPInboundFormat.parse(Data(list.replacingOccurrences(of: "50", with: limit).utf8)); throw Failure(label: "invalid limit") }
                catch MCPInboundFormatError.invalidParameters { count += 1 }
            }
    }
    static func main() async {
        do {
            try await lifecycle()
            try await network()
            try await concurrencyAndLimits()
            try format()
            print("PASS access/tasks: \(count) checks; synthetic only")
        } catch { print("FAIL access/tasks: \(error)"); exit(1) }
    }
}
