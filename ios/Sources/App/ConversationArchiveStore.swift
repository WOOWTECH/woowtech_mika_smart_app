import AssistantPersistence
import Combine
import Foundation

@MainActor final class ConversationArchiveStore: ObservableObject {
    @Published private(set) var state = ConversationArchive()
    @Published private(set) var available = false
    @Published private(set) var error: String?
    private let vault: EncryptedLearningFile?

    var conversations: [ArchivedConversation] {
        state.conversations.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
    }

    var drawerConversations: [ArchivedConversation] { state.drawerConversations }

    init(vault: EncryptedLearningFile) { self.vault = vault; reload() }

    init() {
        do {
            let location = try Self.location(arguments: ProcessInfo.processInfo.arguments)
            let file = EncryptedLearningFile(url: location.url, keys: LearningKeychainStore(service: location.service))
            if location.reset { try file.withExclusiveAccess { try file.save(ConversationArchive(), rotateKey: true) } }
            vault = file
            reload()
        } catch {
            vault = nil
            self.error = Self.readFailure
        }
    }

    func reload() {
        do {
            guard let vault else { throw ConversationArchiveError.unavailable }
            let next = try vault.withExclusiveAccess { try vault.load(ConversationArchive.self) ?? ConversationArchive() }
            state = next; available = true; error = nil
        } catch { available = false; self.error = Self.readFailure }
    }

    /// Match the exact pre-request row. Deletion/replacement cannot be undone by
    /// a late response, and unrelated conversation deletion does not block this row.
    /// Returns the conversations that gave way to make room (see ConversationArchive.save).
    @discardableResult
    func save(_ record: ArchivedConversation, expected: ArchivedConversation?) throws -> [UUID] {
        guard available, let vault else { throw ConversationArchiveError.unavailable }
        var evicted: [UUID] = []
        let next = try vault.withExclusiveAccess {
            var latest = try vault.load(ConversationArchive.self) ?? ConversationArchive()
            let current = latest.conversations.first(where: { $0.id == record.id })
            // Display-only renames and pins may happen while a request runs.
            guard current?.id == expected?.id,
                  current?.destination == expected?.destination,
                  current?.updatedAt == expected?.updatedAt,
                  current?.turns == expected?.turns else {
                throw ConversationArchiveError.staleConversation
            }
            evicted = try latest.save(record)
            try vault.save(latest)
            return latest
        }
        state = next; error = nil
        return evicted
    }

    /// Publish only after the complete branch snapshot is encrypted and saved.
    /// Returns the conversations that gave way to make room.
    @discardableResult
    func commitBranch(_ plan: ConversationBranchPlan, isBusy: Bool, hasUnfinishedOrUnsavedTurn: Bool) throws -> [UUID] {
        guard available, let vault else { throw ConversationArchiveError.unavailable }
        var evicted: [UUID] = []
        let next = try vault.withExclusiveAccess {
            let latest = try vault.load(ConversationArchive.self) ?? ConversationArchive()
            let next = try plan.applying(to: latest, isBusy: isBusy,
                                         hasUnfinishedOrUnsavedTurn: hasUnfinishedOrUnsavedTurn)
            let kept = Set(next.conversations.map(\.id))
            evicted = latest.conversations.map(\.id).filter { !kept.contains($0) }
            try vault.save(next)
            return next
        }
        state = next; error = nil
        return evicted
    }

    func rename(id: UUID, expectedTitle: String?, to title: String) throws {
        guard available, let vault else { throw ConversationArchiveError.unavailable }
        let next = try vault.withExclusiveAccess {
            var latest = try vault.load(ConversationArchive.self) ?? ConversationArchive()
            try latest.rename(id: id, expectedTitle: expectedTitle, to: title)
            try vault.save(latest)
            return latest
        }
        state = next; error = nil
    }

    func setPinned(id: UUID, expectedPinnedAt: Date?, pinned: Bool) throws {
        guard available, let vault else { throw ConversationArchiveError.unavailable }
        let next = try vault.withExclusiveAccess {
            var latest = try vault.load(ConversationArchive.self) ?? ConversationArchive()
            try latest.setPinned(id: id, expectedPinnedAt: expectedPinnedAt, pinned: pinned)
            try vault.save(latest)
            return latest
        }
        state = next; error = nil
    }

    @discardableResult func delete(id: UUID) -> Bool {
        do {
            guard available, let vault else { throw ConversationArchiveError.unavailable }
            let next = try vault.withExclusiveAccess {
                var latest = try vault.load(ConversationArchive.self) ?? ConversationArchive()
                try latest.delete(id: id)
                try vault.save(latest)
                return latest
            }
            state = next; error = nil
            return true
        } catch { self.error = "刪除未儲存，原對話仍保留。請解鎖後重試。"; return false }
    }

    private static let readFailure = "無法讀取加密對話，原檔保留且不會被覆寫。請解鎖後重新讀取。"

    static func location(arguments: [String], supportDirectory: () throws -> URL = {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }) throws -> (url: URL, service: String, reset: Bool) {
        var scope = "personal", reset = false
        #if DEBUG
        let flags = ["-UITestMode", "-LiveModelUITest", "-UITestNamespace", "-LiveModelUITestNamespace",
                     "-UITestResetStorage", "-LiveModelUITestCleanup"]
        if flags.contains(where: arguments.contains) {
            guard flags.allSatisfy({ flag in arguments.filter { $0 == flag }.count <= 1 }),
                  arguments.contains("-UITestMode") != arguments.contains("-LiveModelUITest")
            else { throw ConversationArchiveError.invalidData }
            let live = arguments.contains("-LiveModelUITest")
            let flag = live ? "-LiveModelUITestNamespace" : "-UITestNamespace"
            let other = live ? "-UITestNamespace" : "-LiveModelUITestNamespace"
            guard !arguments.contains(other), live || !arguments.contains("-LiveModelUITestCleanup"),
                  let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1),
                  let id = UUID(uuidString: arguments[i + 1]) else { throw ConversationArchiveError.invalidData }
            scope = "test-" + id.uuidString
            reset = arguments.contains("-UITestResetStorage") || arguments.contains("-LiveModelUITestCleanup")
        }
        #endif
        let root = try supportDirectory()
        return (root.appendingPathComponent("Conversations/" + scope, isDirectory: true).appendingPathComponent("conversations.vault"),
                "io.woowtech.assistant.conversations.v1." + scope, reset)
    }
}
