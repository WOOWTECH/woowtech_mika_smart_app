import CryptoKit
import Dispatch
import Foundation

/// Raw address bytes must come from the accepted socket, never a forwarded header.
public struct MCPInboundPeer: Hashable, Sendable {
    private let bytes: [UInt8]
    public init?(addressBytes: [UInt8]) {
        guard addressBytes.count == 4 || addressBytes.count == 16 else { return nil }
        // Canonicalize IPv4-mapped IPv6 so it cannot bypass per-peer limits.
        if addressBytes.count == 16 && addressBytes.prefix(10).allSatisfy({ $0 == 0 }) &&
            addressBytes[10] == 255 && addressBytes[11] == 255 {
            bytes = Array(addressBytes.suffix(4))
        } else { bytes = addressBytes }
    }
    fileprivate var loopback: Bool {
        if bytes.count == 4 { return bytes[0] == 127 }
        return bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
    }
    fileprivate var privateNetwork: Bool {
        if loopback { return true }
        if bytes.count == 4 {
            return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
                (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 100 && (64...127).contains(bytes[1])) ||
                (bytes[0] == 169 && bytes[1] == 254)
        }
        return bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
    }
}

public struct MCPInboundHeader: Sendable {
    public let name: String
    public let value: String
    public init(_ name: String, _ value: String) { self.name = name; self.value = value }
}
public enum MCPInboundScope: Sendable { case loopback, privateNetworks }
public enum MCPInboundAccessError: Error, Equatable, Sendable {
    case disabled, sourceRejected, browserRejected, malformedHeaders, unauthorized, rateLimited, capacity, invalidConnection, clockFailure
    case invalidToken, busy, unsupported, conflict, missing, invalidReview
}
public enum MCPInboundTaskPhase: Sendable, Equatable { case queued, running, waitingForAnswer, waitingForLocalApproval, finished, cancelled }
public struct MCPInboundQuestion: Sendable, Equatable {
    public let id: UUID
    public let text: String
}
public struct MCPInboundTaskStatus: Sendable, Equatable {
    public let taskID: UUID
    public let phase: MCPInboundTaskPhase
    public let question: MCPInboundQuestion?
    public init(taskID: UUID, phase: MCPInboundTaskPhase, question: MCPInboundQuestion? = nil) {
        self.taskID = taskID; self.phase = phase; self.question = question
    }
}
/// Host-only generation handle. It cannot authorize device or network work.
public struct MCPInboundHostLease: Sendable, Equatable {
    fileprivate let taskID: UUID
    fileprivate let generation: UUID
}
/// Accepted means queued as untrusted text; it does not mean applied or approved.
public struct MCPInboundInput: Sendable, Equatable {
    public let requestID: UUID
    public let text: String
}
public struct MCPInboundWaitResult: Sendable, Equatable {
    public let status: MCPInboundTaskStatus
    public let changed: Bool
}
public enum MCPInboundStageResult: Sendable, Equatable {
    case review(MCPInboundReview)
    case existing(MCPInboundTaskStatus)
}

/// Offline, process-local state machine. Nothing here creates a listener,
/// makes a model request, stores secrets, or executes any task. A future host
/// MUST provide real socket peer bytes, user controls, and atomic transport /
/// configuration revalidation; caller-provided values are not proof of origin.
public actor MCPInboundAccessTasks {
    private struct Connection { let peer: MCPInboundPeer; let created: UInt64 }
    private struct Failure { var count: Int; var since: UInt64; var lockedUntil: UInt64 }
    private struct Record {
        let connection: UUID
        let binding: MCPInboundReviewBinding
        let task: MCPInboundModelTask
        var phase: MCPInboundTaskPhase
        var runGeneration: UUID? = nil
        var question: MCPInboundQuestion? = nil
        var answers: [UUID: AnswerReceipt] = [:]
        var pendingAnswer: MCPInboundInput? = nil
        var steers: [UUID: String] = [:]
        var pendingSteers: [MCPInboundInput] = []
    }
    private struct AnswerReceipt { let questionID: UUID; let text: String }
    private struct Pending { let review: MCPInboundReview; let taskID: UUID }
    private let clock: @Sendable () -> UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    private var waiters = 0
    private let challenge = Data("woow-inbound-token-check-v1".utf8)
    private var lastTime: UInt64 = 0
    private var enabled = false, active = false
    private var scope: MCPInboundScope = .loopback
    private var tokenMAC: HMAC<SHA256>.MAC?
    private var connections: [UUID: Connection] = [:]
    private var failures: [MCPInboundPeer: Failure] = [:]
    private var pending: Pending?
    private var records: [UUID: Record] = [:]
    private var order: [UUID] = []
    private let window: UInt64 = 60_000
    public init(clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds / 1_000_000 },
                sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.clock = clock; self.sleep = sleep
    }

    /// Host-only user action. Rotation/reconfiguration revokes every connection
    /// and review; a 43-character base64url token must be generated securely by
    /// the future host. Format validation alone does not establish entropy.
    public func enableByUser(scope: MCPInboundScope, token: Data) throws {
        revoke()
        guard active else { throw MCPInboundAccessError.disabled }
        guard validToken(token) else { throw MCPInboundAccessError.invalidToken }
        self.scope = scope
        tokenMAC = HMAC<SHA256>.authenticationCode(for: challenge, using: SymmetricKey(data: token))
        enabled = true
    }
    public func disableByUser() { revoke() }
    /// Inactive revokes and disables; returning active requires a new local enable.
    public func setForegroundActive(_ value: Bool) { active = value; if !value { revoke() } }
    private func revoke() {
        enabled = false; tokenMAC = nil; connections.removeAll(); pending = nil
        records.removeAll(); order.removeAll()
    }
    /// Host-only callback for the actual transport closure, never a remote command.
    public func connectionDidClose(_ id: UUID) {
        connections.removeValue(forKey: id)
        if pending?.review.binding.connection == id { pending = nil }
        let ids = records.filter { $0.value.connection == id }.map(\.key)
        for taskID in ids { records.removeValue(forKey: taskID) }
        order.removeAll { ids.contains($0) }
    }

    public func open(peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> UUID {
        try authenticate(peer: peer, headers: headers)
        guard connections.count < 32 else { throw MCPInboundAccessError.capacity }
        let id = UUID(); connections[id] = Connection(peer: peer, created: lastTime); return id
    }
    /// The authorization header and socket peer are checked on every request.
    public func check(connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws {
        try authenticate(peer: peer, headers: headers)
        guard try currentConnection(connection)?.peer == peer else { throw MCPInboundAccessError.invalidConnection }
    }

    /// One review at a time. Without a client request_id, each accepted start
    /// receives a new server ID and retries cannot be distinguished.
    public func stage(task: MCPInboundModelTask, binding: MCPInboundReviewBinding,
                      peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> MCPInboundStageResult {
        try check(connection: binding.connection, peer: peer, headers: headers)
        guard task.conversation == nil else { throw MCPInboundAccessError.unsupported }
        guard !task.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              task.goal.utf16.count <= 4000 else { throw MCPInboundAccessError.unsupported }
        if let taskID = task.requestID, let record = records[taskID] {
            guard record.connection == binding.connection, record.binding == binding, record.task == task else { throw MCPInboundAccessError.conflict }
            return .existing(statusValue(taskID, record))
        }
        if let pending {
            guard task.requestID != nil, pending.review.binding == binding, pending.review.task == task else { throw MCPInboundAccessError.busy }
            return .review(pending.review)
        }
        guard records.count < 50 else { throw MCPInboundAccessError.capacity }
        var taskID = task.requestID ?? UUID()
        while records[taskID] != nil && task.requestID == nil { taskID = UUID() }
        let review = MCPInboundReview(id: UUID(), binding: binding, task: task)
        pending = Pending(review: review, taskID: taskID)
        return .review(review)
    }
    /// Only a local review action may call this. It queues an inert record; no
    /// operation or model request is started. No remote input is approval.
    public func approveLocally(reviewID: UUID, current: MCPInboundReviewBinding) throws -> MCPInboundTaskStatus {
        // A callback for an older review has no authority over a newer one.
        guard let pending, pending.review.id == reviewID else { throw MCPInboundAccessError.invalidReview }
        guard enabled, active, pending.review.binding == current,
              let connection = try currentConnection(current.connection),
              !(failures[connection.peer].map { $0.lockedUntil > lastTime } ?? false),
              records[pending.taskID] == nil else {
            self.pending = nil; throw MCPInboundAccessError.invalidReview
        }
        let id = pending.taskID
        records[id] = Record(connection: current.connection, binding: current, task: pending.review.task, phase: .queued)
        order.append(id); self.pending = nil
        return .init(taskID: id, phase: .queued)
    }
    public func discardReview() { pending = nil }
    public func status(taskID: UUID, connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> MCPInboundTaskStatus {
        try check(connection: connection, peer: peer, headers: headers)
        guard let record = records[taskID], record.connection == connection else { throw MCPInboundAccessError.missing }
        return statusValue(taskID, record)
    }
    private func statusValue(_ id: UUID, _ record: Record) -> MCPInboundTaskStatus {
        .init(taskID: id, phase: record.phase, question: record.question)
    }
    public func list(limit: Int, connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> [MCPInboundTaskStatus] {
        try check(connection: connection, peer: peer, headers: headers)
        guard (1...50).contains(limit) else { throw MCPInboundAccessError.unsupported }
        return order.reversed().compactMap { id in
            guard let record = records[id], record.connection == connection else { return nil }
            return statusValue(id, record)
        }.prefix(limit).map { $0 }
    }
    /// Cancels only this in-memory state, not an already dispatched request.
    public func cancel(taskID: UUID, connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> Bool {
        try check(connection: connection, peer: peer, headers: headers)
        guard var record = records[taskID], record.connection == connection else { throw MCPInboundAccessError.missing }
        guard record.phase != .cancelled && record.phase != .finished else { return false }
        record.phase = .cancelled; record.runGeneration = nil; record.question = nil
        record.pendingAnswer = nil; record.pendingSteers.removeAll()
        records[taskID] = record; return true
    }

    /// Local host callbacks only model state; they do not start or control an
    /// executor. Future hosts must separately bind authorization and transport.
    public func hostBegin(taskID: UUID, binding: MCPInboundReviewBinding) throws -> MCPInboundHostLease {
        guard enabled, active, try currentConnection(binding.connection) != nil,
              var record = records[taskID], record.binding == binding, record.phase == .queued else { throw MCPInboundAccessError.conflict }
        let generation = UUID(); record.runGeneration = generation; record.phase = .running
        records[taskID] = record
        return MCPInboundHostLease(taskID: taskID, generation: generation)
    }
    private func hostRecord(_ lease: MCPInboundHostLease) throws -> Record {
        guard enabled, active, let record = records[lease.taskID],
              try currentConnection(record.connection) != nil, record.runGeneration == lease.generation,
              record.phase != .cancelled, record.phase != .finished else { throw MCPInboundAccessError.conflict }
        return record
    }
    /// A host-reported state transition only; it does not run or persist work.
    /// A future executor must call this only after its own completion is settled.
    public func hostFinish(lease: MCPInboundHostLease) throws {
        var record = try hostRecord(lease)
        guard record.phase == .running, record.pendingAnswer == nil, record.pendingSteers.isEmpty else { throw MCPInboundAccessError.conflict }
        record.phase = .finished; record.runGeneration = nil; records[lease.taskID] = record
    }
    public func hostAsk(_ text: String, lease: MCPInboundHostLease) throws -> MCPInboundQuestion {
        var record = try hostRecord(lease)
        let clean = try checkedText(text, maximum: 2000)
        guard record.phase == .running, record.pendingAnswer == nil else { throw MCPInboundAccessError.conflict }
        let question = MCPInboundQuestion(id: UUID(), text: clean)
        record.question = question; record.phase = .waitingForAnswer; records[lease.taskID] = record
        return question
    }
    /// An app-local approval is distinct from a question and cannot be answered remotely.
    public func hostRequireLocalApproval(lease: MCPInboundHostLease) throws {
        var record = try hostRecord(lease)
        guard record.phase == .running else { throw MCPInboundAccessError.conflict }
        record.phase = .waitingForLocalApproval; records[lease.taskID] = record
    }
    public func hostResumeAfterLocalApproval(lease: MCPInboundHostLease) throws {
        var record = try hostRecord(lease)
        guard record.phase == .waitingForLocalApproval else { throw MCPInboundAccessError.conflict }
        record.phase = .running; records[lease.taskID] = record
    }
    /// Optional IDs can bind a question and deduplicate retries. Without them,
    /// each request targets the question open when the actor processes it.
    @discardableResult public func answer(taskID: UUID, questionID: UUID? = nil, requestID: UUID? = nil, text: String,
                                         connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> UUID {
        try check(connection: connection, peer: peer, headers: headers)
        guard var record = records[taskID], record.connection == connection else { throw MCPInboundAccessError.missing }
        let clean = try checkedText(text, maximum: 2000)
        if let requestID {
            guard record.steers[requestID] == nil else { throw MCPInboundAccessError.conflict }
            if let receipt = record.answers[requestID] {
                guard (questionID == nil || receipt.questionID == questionID), receipt.text == clean else { throw MCPInboundAccessError.conflict }
                return requestID
            }
        }
        guard record.phase == .waitingForAnswer, let current = record.question,
              questionID == nil || current.id == questionID,
              record.pendingAnswer == nil else { throw MCPInboundAccessError.conflict }
        guard record.answers.count < 64 else { throw MCPInboundAccessError.capacity }
        var operationID = requestID ?? UUID()
        while requestID == nil && (record.answers[operationID] != nil || record.steers[operationID] != nil) { operationID = UUID() }
        record.answers[operationID] = AnswerReceipt(questionID: current.id, text: clean)
        record.pendingAnswer = MCPInboundInput(requestID: operationID, text: clean)
        record.question = nil; record.phase = .running; records[taskID] = record
        return operationID
    }
    public func hostTakeAnswer(lease: MCPInboundHostLease) throws -> MCPInboundInput? {
        var record = try hostRecord(lease)
        guard record.phase == .running else { throw MCPInboundAccessError.conflict }
        let result = record.pendingAnswer; record.pendingAnswer = nil; records[lease.taskID] = record
        return result
    }
    /// With no request_id, each accepted instruction gets a new message ID,
    /// matching Android's non-idempotent submission semantics.
    @discardableResult public func steer(taskID: UUID, requestID: UUID? = nil, text: String,
                                        connection: UUID, peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws -> UUID {
        try check(connection: connection, peer: peer, headers: headers)
        guard var record = records[taskID], record.connection == connection else { throw MCPInboundAccessError.missing }
        let clean = try checkedText(text, maximum: 4000)
        if let requestID {
            guard record.answers[requestID] == nil else { throw MCPInboundAccessError.conflict }
            if let previous = record.steers[requestID] {
                guard previous == clean else { throw MCPInboundAccessError.conflict }
                return requestID
            }
        }
        guard record.phase == .running else { throw MCPInboundAccessError.conflict }
        guard record.steers.count < 64, record.pendingSteers.count < 16 else { throw MCPInboundAccessError.capacity }
        var operationID = requestID ?? UUID()
        while requestID == nil && (record.steers[operationID] != nil || record.answers[operationID] != nil) { operationID = UUID() }
        record.steers[operationID] = clean
        record.pendingSteers.append(MCPInboundInput(requestID: operationID, text: clean)); records[taskID] = record
        return operationID
    }
    public func hostTakeSteer(lease: MCPInboundHostLease) throws -> MCPInboundInput? {
        var record = try hostRecord(lease)
        guard record.phase == .running else { throw MCPInboundAccessError.conflict }
        guard !record.pendingSteers.isEmpty else { return nil }
        let result = record.pendingSteers.removeFirst(); records[lease.taskID] = record
        return result
    }
    private func checkedText(_ text: String, maximum: Int) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf16.count <= maximum else { throw MCPInboundAccessError.unsupported }
        return clean
    }

    /// Rechecks the authenticated session and lockout after each suspension.
    /// Timeout or cancellation stops only this wait, never the task. Limit waits.
    public func wait(taskID: UUID, timeoutSeconds: Int = 30, connection: UUID,
                     peer: MCPInboundPeer, headers: [MCPInboundHeader]) async throws -> MCPInboundWaitResult {
        guard (1...50).contains(timeoutSeconds) else { throw MCPInboundAccessError.unsupported }
        try Task.checkCancellation()
        let first = try status(taskID: taskID, connection: connection, peer: peer, headers: headers)
        if first.phase == .cancelled || first.phase == .finished { return .init(status: first, changed: false) }
        guard waiters < 16 else { throw MCPInboundAccessError.capacity }
        let started = try tick(); waiters += 1
        defer { waiters -= 1 }
        while true {
            try Task.checkCancellation()
            let now = try tick()
            let elapsed = now - started
            if elapsed >= UInt64(timeoutSeconds) * 1000 {
                let current = try waitStatus(taskID: taskID, connection: connection, peer: peer)
                try Task.checkCancellation()
                return .init(status: current, changed: current.phase != first.phase)
            }
            let remaining = UInt64(timeoutSeconds) * 1000 - elapsed
            try await sleep(min(remaining, 250) * 1_000_000)
            try Task.checkCancellation()
            let current = try waitStatus(taskID: taskID, connection: connection, peer: peer)
            if current.phase != first.phase || current.phase == .cancelled || current.phase == .finished {
                try Task.checkCancellation()
                return .init(status: current, changed: current.phase != first.phase)
            }
        }
    }

    /// The wait authenticated its immutable headers at entry. Rotation and
    /// lifecycle changes revoke the connection; do not replay authentication on
    /// each poll because successful polling would erase failed-attempt counts.
    private func waitStatus(taskID: UUID, connection: UUID, peer: MCPInboundPeer) throws -> MCPInboundTaskStatus {
        guard enabled, active, tokenMAC != nil else { throw MCPInboundAccessError.disabled }
        guard let current = try currentConnection(connection), current.peer == peer else { throw MCPInboundAccessError.invalidConnection }
        if let failure = failures[peer], failure.lockedUntil > lastTime { throw MCPInboundAccessError.rateLimited }
        guard let record = records[taskID], record.connection == connection else { throw MCPInboundAccessError.missing }
        return statusValue(taskID, record)
    }

    private func tick() throws -> UInt64 {
        let now = clock()
        guard now >= lastTime else { revoke(); throw MCPInboundAccessError.clockFailure }
        lastTime = now
        // Expire all peers, not only the handle referenced by this request:
        // stale sessions must not retain a review, task slots or connection slots.
        let expired = connections.compactMap { id, connection in
            now - connection.created >= 300_000 ? id : nil
        }
        for id in expired { connectionDidClose(id) }
        return now
    }
    private func currentConnection(_ id: UUID) throws -> Connection? {
        let now = try tick()
        guard let connection = connections[id] else { return nil }
        if now - connection.created >= 300_000 { connectionDidClose(id); return nil }
        return connection
    }
    private func validToken(_ token: Data) -> Bool {
        token.count == 43 && token.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
    private func authenticate(peer: MCPInboundPeer, headers: [MCPInboundHeader]) throws {
        guard enabled, active, let tokenMAC else { throw MCPInboundAccessError.disabled }
        guard scope == .loopback ? peer.loopback : peer.privateNetwork else { throw MCPInboundAccessError.sourceRejected }
        guard headers.count <= 32, headers.reduce(0, { $0 + $1.name.utf8.count + $1.value.utf8.count }) <= 8192,
              headers.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.allSatisfy {
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) ||
                      [33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126].contains($0)
              } &&
                  !$0.value.utf8.contains(where: { ($0 < 32 && $0 != 9) || $0 == 127 }) }) else { throw MCPInboundAccessError.malformedHeaders }
        let origins = headers.filter { $0.name.lowercased() == "origin" }
        guard origins.isEmpty else { throw MCPInboundAccessError.browserRejected }
        let now = try tick()
        failures = failures.filter { _, failure in
            failure.lockedUntil > now || now - failure.since < window
        }
        if let failure = failures[peer], failure.lockedUntil > now { throw MCPInboundAccessError.rateLimited }
        guard failures[peer] != nil || failures.count < 256 else { throw MCPInboundAccessError.capacity }
        let auth = headers.filter { $0.name.lowercased() == "authorization" }
        // Duplicates are not merged, even if the values match.
        guard auth.count <= 1 else { throw MCPInboundAccessError.malformedHeaders }
        let parts = auth.first?.value.split(separator: " ", omittingEmptySubsequences: false) ?? []
        let presented = parts.count == 2 && parts[0].lowercased() == "bearer" ? Data(parts[1].utf8) : Data()
        let valid = validToken(presented) && HMAC<SHA256>.isValidAuthenticationCode(tokenMAC, authenticating: challenge, using: SymmetricKey(data: presented))
        guard valid else {
            var failure = failures[peer] ?? Failure(count: 0, since: now, lockedUntil: 0)
            if now - failure.since >= window { failure = Failure(count: 0, since: now, lockedUntil: 0) }
            failure.count += 1
            if failure.count >= 5 {
                let (deadline, overflow) = now.addingReportingOverflow(window)
                failure.lockedUntil = overflow ? UInt64.max : deadline
                failure.count = 0; failure.since = now
            }
            failures[peer] = failure
            throw MCPInboundAccessError.unauthorized
        }
        failures.removeValue(forKey: peer)
    }
}
