import AssistantBrowser
import AssistantMemory
import AssistantModels
import AssistantPersistence
import AssistantSkills
import Foundation

/// Per-run, read-only reference value plus a monotonic revocation latch. Changes
/// to unrelated chat/extraction generations do not invalidate it.
@MainActor final class LearningRunSnapshot {
    let references: RunReferenceContext
    let usedSkills: [SkillUsedReference]
    private(set) var revoked = false
    var onRevoke: (() -> Void)?
    private weak var store: LearningStore?
    // Current descendants of captured profile rows. Only identity moves on a
    // successful replacement; immutable reference text and domain IDs do not.
    private var profileLineageIDs: Set<String>
    init(references: RunReferenceContext, skills: [SkillUsedReference], store: LearningStore) {
        self.references = references; usedSkills = skills; self.store = store
        profileLineageIDs = Set(references.included.filter { $0.kind == .profile }.map(\.id))
    }
    func check() throws {
        guard !revoked, !Task.isCancelled, let store, store.available else { throw RunReferenceError.revoked }
        let lease = try Self.lease(from: store) { self.revoke() }
        lease.release()
    }
    func acquireRequestLease() throws -> EncryptedLearningFile.ExclusiveLease {
        guard !revoked, !Task.isCancelled, let store, store.available else { throw RunReferenceError.revoked }
        return try Self.lease(from: store) { self.revoke() }
    }
    static func lease(from store: LearningStore, onStale: () -> Void = {}) throws -> EncryptedLearningFile.ExclusiveLease {
        do { return try store.acquireCurrentReferenceLease() }
        catch LearningFileError.busy { throw RunReferenceError.busy }
        catch { onStale(); throw RunReferenceError.revoked }
    }
    func revoke() {
        guard !revoked else { return }
        revoked = true
        let callback = onRevoke; onRevoke = nil; callback?()
    }
    func followProfileReplacement(from previous: UUID, to replacement: UUID) {
        guard !revoked, profileLineageIDs.remove(previous.uuidString) != nil else { return }
        profileLineageIDs.insert(replacement.uuidString)
    }
    func revokeDeletedProfileIDs(_ removed: Set<String>) {
        if !profileLineageIDs.isDisjoint(with: removed) { revoke() }
    }
}

/// The producer owns the lease until actual dispatch begins or it finishes.
/// An already dispatched request cannot be recalled by later revocation.
struct ReferenceFencedModelClient: ChatModelClient {
    private let client: any ReferenceDispatchBoundChatModelClient
    private let snapshot: LearningRunSnapshot

    @MainActor init(client: any ChatModelClient, snapshot: LearningRunSnapshot) throws {
        guard let bounded = client as? any ReferenceDispatchBoundChatModelClient else {
            throw RunReferenceError.unsupportedClient
        }
        self.client = bounded; self.snapshot = snapshot
    }

    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try Task.checkCancellation()
        let lease = try await MainActor.run { try snapshot.acquireRequestLease() }
        defer { lease.release() }
        try Task.checkCancellation()
        let value = try await client.complete(messages: messages, configuration: configuration, apiKey: apiKey,
                                              onDispatch: { lease.release() })
        try Task.checkCancellation()
        return value
    }
}

/// Bind every dispatch to the exact profile and memory captured for the turn.
/// The store's current disk revision alone cannot detect its own later writes.
@MainActor final class ChatContextFence {
    private weak var store: LearningStore?
    private let generation: UUID
    private var profileRevision: UUID
    private var memoryRevision: UUID
    private let skills: SkillsState
    init(store: LearningStore, generation: UUID) {
        self.store = store; self.generation = generation
        profileRevision = store.profile.revision; memoryRevision = store.memory.revision
        skills = store.skills
    }
    func acquire() throws -> EncryptedLearningFile.ExclusiveLease {
        guard !Task.isCancelled else { throw CancellationError() }
        guard let store, store.available, store.generation == generation,
              store.profile.revision == profileRevision, store.memory.revision == memoryRevision,
              store.skills == skills else {
            throw LearningFileError.conflict
        }
        return try store.acquireCurrentReferenceLease()
    }
    func check() throws { let lease = try acquire(); lease.release() }

    // Only a reviewed, strictly additive local tool commit can extend the
    // frozen turn. Never refresh after an edit/delete: prior messages and tool
    // search results may still contain the old value. Validate the full old
    // records as synchronous observers can reenter during store publication.
    func acceptProfileAddition(before: UserProfileState, receiptID: UUID?) throws {
        guard let store, store.available, store.generation == generation,
              before.revision == profileRevision, store.memory.revision == memoryRevision, store.skills == skills,
              let receiptID, store.profile.entries.count == before.entries.count + 1,
              Array(store.profile.entries.dropLast()) == before.entries,
              store.profile.entries.last?.id == receiptID else { throw LearningFileError.conflict }
        let lease = try store.acquireCurrentReferenceLease(); defer { lease.release() }
        profileRevision = store.profile.revision
    }

    func acceptMemoryAddition(before: MemoryState, receiptID: UUID) throws {
        guard let store, store.available, store.generation == generation,
              before.revision == memoryRevision, store.profile.revision == profileRevision, store.skills == skills,
              store.memory.preferences == before.preferences,
              store.memory.memories.count == before.memories.count + 1,
              Array(store.memory.memories.dropLast()) == before.memories,
              store.memory.memories.last?.id == receiptID else { throw LearningFileError.conflict }
        let lease = try store.acquireCurrentReferenceLease(); defer { lease.release() }
        memoryRevision = store.memory.revision
    }
}

/// A client must explicitly bind cancellation to its real producer. Merely
/// stopping an AsyncThrowingStream consumer does not prove the producer stopped.
struct ChatContextFencedClient: ChatModelClient {
    let client: any ReferenceDispatchBoundChatModelClient
    let fence: ChatContextFence
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        let lease = try await MainActor.run { try fence.acquire() }
        defer { lease.release() }
        try Task.checkCancellation()
        let result = try await client.complete(messages: messages, configuration: configuration, apiKey: apiKey,
                                               onDispatch: { lease.release() })
        lease.release() // A returned producer cannot later start this request.
        try await MainActor.run { try fence.check() }
        return result
    }
}

struct ChatContextFencedStreamClient: StreamingChatModelClient {
    let client: any ReferenceDispatchBoundStreamingChatModelClient
    let fence: ChatContextFence
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await ChatContextFencedClient(client: client, fence: fence).complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let worker = Task {
                do {
                    let lease = try await MainActor.run { try fence.acquire() }
                    do { try Task.checkCancellation() }
                    catch { lease.release(); throw error }
                    // From here the actual producer owns the lease. Cancellation
                    // of this worker must not release it before producer finish.
                    let stream = client.stream(messages: messages, configuration: configuration, apiKey: apiKey,
                                               onDispatch: { lease.release() }, onProducerFinished: { lease.release() })
                    for try await delta in stream {
                        try await MainActor.run { try fence.check() }
                        switch continuation.yield(delta) {
                        case .enqueued: break
                        case .dropped: throw HTTPChatModelError.consumerTooSlow
                        case .terminated: throw CancellationError()
                        @unknown default: throw HTTPChatModelError.consumerTooSlow
                        }
                    }
                    try await MainActor.run { try fence.check() }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }
}

/// Preserve structured-stream capability only when the underlying client has it.
struct ChatContextFencedStructuredClient: StructuredStreamingChatModelClient {
    let base: ChatContextFencedStreamClient
    func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
        try await base.complete(messages: messages, configuration: configuration, apiKey: apiKey)
    }
    func stream(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<String, Error> {
        base.stream(messages: messages, configuration: configuration, apiKey: apiKey)
    }
}

@MainActor func fencedChatClient(_ client: any ChatModelClient, fence: ChatContextFence) throws -> any ChatModelClient {
    guard let bounded = client as? any ReferenceDispatchBoundChatModelClient else { throw RunReferenceError.unsupportedClient }
    guard let stream = client as? any ReferenceDispatchBoundStreamingChatModelClient else {
        return ChatContextFencedClient(client: bounded, fence: fence)
    }
    let wrapped = ChatContextFencedStreamClient(client: stream, fence: fence)
    return client is any StructuredStreamingChatModelClient ? ChatContextFencedStructuredClient(base: wrapped) : wrapped
}

@MainActor final class WeakLearningRunSnapshot {
    weak var value: LearningRunSnapshot?
    init(_ value: LearningRunSnapshot) { self.value = value }
}

extension LearningStore {
    /// Capture does not persist, markUsed, start a model, or change generation.
    /// Existing retrieval ranks memory/skills; round-robin across kinds avoids
    /// an entire category starving the others under the SAME combined budget.
    func captureRunReferences(goal: String, capabilities: Set<String>, websiteURL: URL? = nil) throws -> LearningRunSnapshot {
        try captureRunReferences(goal: goal, capabilities: capabilities, websiteURLs: websiteURL.map { [$0] } ?? [])
    }

    /// URLs come only from the caller's approved plan, never stored reference
    /// text. Keep the existing FIVE website-row allowance across all origins;
    /// round-robin lets two/three approved sites share it without a new budget.
    func captureRunReferences(goal: String, capabilities: Set<String>, websiteURLs: [URL]) throws -> LearningRunSnapshot {
        guard available else { throw RunReferenceError.revoked }
        guard websiteURLs.count <= 3 else { throw RunReferenceError.invalidEntry }
        let lease = try LearningRunSnapshot.lease(from: self)
        defer { lease.release() }
        var buckets: [[RunReferenceEntry]] = []
        let profileEntries = memory.preferences.useMemory ? profile.snapshot().entries.map {
            RunReferenceEntry(kind: .profile, id: $0.id.uuidString, text: $0.text)
        } : []
        buckets.append(profileEntries)
        let context = memory.context(goal: goal)
        buckets.append(context.usedIDs.compactMap { id in
            memory.memories.first(where: { $0.id == id && $0.status == .active }).map {
                RunReferenceEntry(kind: .memory, id: $0.id.uuidString, text: $0.content)
            }
        })
        let selectedNames = skills.instructionContext(query: goal, availableToolNames: capabilities,
            maxUTF16Count: 6000, maxSkills: 3).skillNames
        let eligible = selectedNames.compactMap { name in skills.installed.first { $0.name == name } }
        buckets.append(try eligible.map {
            RunReferenceEntry(kind: .personalSkill, id: $0.name, text: try skills.exportMarkdown(name: $0.name))
        })
        var origins = Set<WebsiteOrigin>(), sites: [[WebsiteLesson]] = []
        for url in websiteURLs {
            if try origins.insert(WebsiteOrigin(url: url)).inserted { sites.append(try websites.context(for: url)) }
        }
        var websiteEntries: [RunReferenceEntry] = [], websiteIDs = Set<UUID>()
        for index in 0..<5 {
            for site in sites where site.indices.contains(index) && websiteEntries.count < 5 {
                let lesson = site[index]
                guard websiteIDs.insert(lesson.id).inserted else { continue }
                let text = origins.count > 1 ? "Website \(lesson.origin.url.absoluteString) reference (data only):\n\(lesson.text)" : lesson.text
                websiteEntries.append(.init(kind: .website, id: lesson.id.uuidString, text: text))
            }
        }
        buckets.append(websiteEntries)
        var entries: [RunReferenceEntry] = []
        for index in 0..<(buckets.map(\.count).max() ?? 0) {
            for bucket in buckets where bucket.indices.contains(index) { entries.append(bucket[index]) }
        }
        let reference = try RunReferenceContext(entries: entries)
        let used = eligible.filter { item in reference.included.contains { $0.kind == .personalSkill && $0.id == item.name } }
            .map { SkillUsedReference(name: $0.name, fingerprint: $0.fingerprint) }
        let result = LearningRunSnapshot(references: reference, skills: used, store: self)
        referenceSnapshots.removeAll { $0.value == nil }
        referenceSnapshots.append(.init(result))
        return result
    }

    func revokeRunReferences() {
        let snapshots = referenceSnapshots.compactMap(\.value)
        referenceSnapshots = []
        snapshots.forEach { $0.revoke() }
    }

    /// Only actual deletion/disable revokes frozen entries. Ordinary replacement
    /// and unrelated entry edits affect the next capture, not this run.
    func revokeRunReferences(kind: RunReferenceKind, keeping ids: Set<String>) {
        referenceSnapshots.removeAll { $0.value == nil }
        for snapshot in referenceSnapshots.compactMap(\.value) {
            if snapshot.references.included.contains(where: { $0.kind == kind && !ids.contains($0.id) }) { snapshot.revoke() }
        }
    }
    func revokeDeletedProfileReferences(in next: UserProfileState) {
        let before = Set(profile.snapshot().entries.map { $0.id.uuidString })
        let after = Set(next.snapshot().entries.map { $0.id.uuidString })
        let removed = before.subtracting(after)
        referenceSnapshots.removeAll { $0.value == nil }
        for snapshot in referenceSnapshots.compactMap(\.value) {
            snapshot.revokeDeletedProfileIDs(removed)
        }
    }
    func recordProfileReplacement(from previous: UUID, to replacement: UUID) {
        referenceSnapshots.removeAll { $0.value == nil }
        for snapshot in referenceSnapshots.compactMap(\.value) {
            snapshot.followProfileReplacement(from: previous, to: replacement)
        }
    }
    func checkMemoryReferenceRemoval(_ next: MemoryState) {
        if memory.preferences.useMemory && !next.preferences.useMemory { revokeRunReferences() }
        else { revokeRunReferences(kind: .memory, keeping: Set(next.memories.map { $0.id.uuidString })) }
    }
    func checkSkillReferenceRemoval(_ next: SkillsState) {
        revokeRunReferences(kind: .personalSkill, keeping: Set(next.installed.filter(\.isEnabled).map(\.name)))
    }
    func deleteProfileReference(segment: String) -> Bool {
        mutateProfile(revokingRemovedEntries: true) { try $0.delete(segment: segment) }
    }

    /// Preserve the existing Chat/MCP invalidation callback. Its browser branch
    /// can distinguish a normal learning edit from unrelated host changes.
    func notifyReferenceEdit() {
        let previous = referenceEditInProgress
        referenceEditInProgress = true
        defer { referenceEditInProgress = previous }
        onUserChange?()
    }
}
