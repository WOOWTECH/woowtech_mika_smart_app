import AssistantPersistence
import Foundation

private final class ArchiveLockTestKeys: LearningKeyStore {
    func read(id: String) throws -> Data? { nil }
    func insert(_ key: Data, id: String) throws {}
    func remove(id: String) throws {}
    func removeAll(except id: String) throws {}
}

enum ConversationArchiveChecks {
    struct Failure: Error { let name: String }
    struct Assertions {
        var count = 0
        mutating func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try value() else { throw Failure(name: name) }; count += 1
        }
        mutating func rejects(_ name: String, _ body: () throws -> Void) throws {
            do { try body() } catch { count += 1; return }
            throw Failure(name: name)
        }
    }
    static func destination() throws -> ConversationDestination {
        try .init(baseURL: "https://archive.example.invalid/v1", model: "fixture", credentialAccount: UUID())
    }

    static func independentVaultLocks() throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("woow-vault-lock-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("archive.vault")
        let first = EncryptedLearningFile(url: path, keys: ArchiveLockTestKeys())
        let second = EncryptedLearningFile(url: path, keys: ArchiveLockTestKeys())
        let held = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0), entered = DispatchSemaphore(value: 0)
        let group = DispatchGroup(), lock = NSLock()
        var errors = 0
        func failed() { lock.lock(); errors += 1; lock.unlock() }
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do { try first.withExclusiveAccess { held.signal(); release.wait() } }
            catch { failed(); held.signal() }
        }
        let acquired = held.wait(timeout: .now() + 5) == .success
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            started.signal()
            do { try second.withExclusiveAccess { entered.signal() } }
            catch { failed(); entered.signal() }
        }
        let secondStarted = started.wait(timeout: .now() + 5) == .success
        let blocked = entered.wait(timeout: .now() + 0.2) == .timedOut
        release.signal()
        let laterEntered = entered.wait(timeout: .now() + 5) == .success
        let finished = group.wait(timeout: .now() + 5) == .success
        lock.lock(); let errorCount = errors; lock.unlock()
        guard acquired && secondStarted && blocked && laterEntered && finished && errorCount == 0 else {
            throw Failure(name: "independent vault instances must serialize access to the same archive")
        }
        return 1
    }
    static func row(destination: ConversationDestination, turns: [ArchivedConversationTurn]? = nil) throws -> ArchivedConversation {
        try .init(id: UUID(), destination: destination, updatedAt: Date(timeIntervalSince1970: 100),
                  turns: turns ?? [.init(userText: "Remember this actual request", assistantText: "Completed answer")])
    }

    /// The pre-rename reader knew only v1/v2 and had no customTitle field.
    private struct LegacyV2Reader: Decodable {
        struct Row: Decodable {
            let id: UUID
            let destination: ConversationDestination
            let updatedAt: Date
            let turns: [ArchivedConversationTurn]
        }
        let version: Int
        let conversations: [Row]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            guard version == 1 || version == 2 else { throw ConversationArchiveError.invalidData }
            conversations = try c.decode([Row].self, forKey: .conversations)
        }
        private enum CodingKeys: String, CodingKey { case version, conversations }
    }

    static func versionCompatibility() throws -> Int {
        var a = Assertions(); let dest = try destination(); let first = try row(destination: dest)
        var archive = ConversationArchive()
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any]
        try a.check(empty["version"] as? Int == 2, "empty archive stays v2")
        try archive.save(first)
        let plainData = try JSONEncoder().encode(archive)
        let plain = try JSONSerialization.jsonObject(with: plainData) as! [String: Any]
        let plainRows = plain["conversations"] as! [[String: Any]]
        try a.check(plain["version"] as? Int == 2 && plainRows.count == 1
                    && plainRows[0]["customTitle"] == nil && plainRows[0]["pinnedAt"] == nil,
                    "archive without user metadata has original v2 shape")
        let oldRead = try JSONDecoder().decode(LegacyV2Reader.self, from: plainData)
        try a.check(oldRead.version == 2 && oldRead.conversations[0].id == first.id
                    && oldRead.conversations[0].destination == first.destination
                    && oldRead.conversations[0].turns == first.turns, "old reader accepts exact unrenamed data")
        var oldest = plain; oldest["version"] = 1
        var fromV1 = try JSONDecoder().decode(ConversationArchive.self,
            from: JSONSerialization.data(withJSONObject: oldest))
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(fromV1)) as! [String: Any])["version"] as? Int == 2,
                    "v1 import writes v2, never v3 before rename")
        let appended = try ArchivedConversation(id: first.id, destination: dest, updatedAt: Date(),
            turns: first.turns + [.init(userText: "Later", assistantText: "Reply")])
        try fromV1.save(appended)
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(fromV1)) as! [String: Any])["version"] as? Int == 2,
                    "ordinary save after v1 import remains v2")
        var fromV2 = try JSONDecoder().decode(ConversationArchive.self, from: plainData)
        try fromV2.save(appended)
        let rewritten = try JSONEncoder().encode(fromV2)
        try a.check((try JSONSerialization.jsonObject(with: rewritten) as! [String: Any])["version"] as? Int == 2
                    && (try JSONDecoder().decode(LegacyV2Reader.self, from: rewritten)).conversations[0].turns.count == 2,
                    "unrenamed v2 writeback and completed reply stay readable by old reader")
        try fromV2.rename(id: first.id, expectedTitle: nil, to: "私有標題")
        let titled = try JSONEncoder().encode(fromV2)
        let titledJSON = try JSONSerialization.jsonObject(with: titled) as! [String: Any]
        try a.check(titledJSON["version"] as? Int == 3
                    && (titledJSON["conversations"] as! [[String: Any]])[0]["customTitle"] as? String == "私有標題",
                    "first custom title upgrades exactly to v3")
        try a.rejects("old reader rejects v3 instead of silently dropping title") {
            _ = try JSONDecoder().decode(LegacyV2Reader.self, from: titled)
        }
        var reopened = try JSONDecoder().decode(ConversationArchive.self, from: titled)
        try a.check(reopened == fromV2, "new reader restores v3 version and title")
        var firstPinOnV3 = reopened
        let pinTime = Date(timeIntervalSince1970: 1_000)
        try firstPinOnV3.setPinned(id: first.id, expectedPinnedAt: nil, pinned: true, at: pinTime)
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(firstPinOnV3)) as! [String: Any])["version"] as? Int == 4
                    && firstPinOnV3.conversations[0].customTitle == "私有標題"
                    && firstPinOnV3.conversations[0].pinnedAt == pinTime,
                    "first pin on old unpinned v3 upgrades to v4 without losing title")
        try firstPinOnV3.setPinned(id: first.id, expectedPinnedAt: pinTime, pinned: false)
        let unpinnedV4 = try JSONEncoder().encode(firstPinOnV3)
        try a.check((try JSONSerialization.jsonObject(with: unpinnedV4) as! [String: Any])["version"] as? Int == 4
                    && (try JSONDecoder().decode(ConversationArchive.self, from: unpinnedV4)) == firstPinOnV3,
                    "cancelled pin after old v3 cannot downgrade and round-trips")
        try reopened.delete(id: first.id)
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(reopened)) as! [String: Any])["version"] as? Int == 3,
                    "deleting last titled record cannot downgrade archive")
        let plainSecond = try row(destination: dest)
        try reopened.save(plainSecond)
        let afterDelete = try JSONEncoder().encode(reopened)
        try a.check((try JSONSerialization.jsonObject(with: afterDelete) as! [String: Any])["version"] as? Int == 3
                    && (try JSONDecoder().decode(ConversationArchive.self, from: afterDelete)) == reopened,
                    "title-only v3 remains v3 after later unrenamed writes and reload")
        try a.rejects("old reader still rejects titleless archive with v3 history") {
            _ = try JSONDecoder().decode(LegacyV2Reader.self, from: afterDelete)
        }
        return a.count
    }

    static func roundTripAndIdentity() throws -> Int {
        var a = Assertions(); var state = ConversationArchive(); let dest = try destination(); let first = try row(destination: dest)
        try state.save(first)
        try a.check(try JSONDecoder().decode(ConversationArchive.self, from: JSONEncoder().encode(state)) == state, "exact Codable roundtrip")
        let next = try ArchivedConversation(id: first.id, destination: dest, updatedAt: Date(),
            turns: first.turns + [.init(userText: "Continue", assistantText: "Second actual answer")])
        try state.save(next); try a.check(state.conversations[0].turns.count == 2, "append retains old pair")
        // Like the Play build a conversation is not tied to its model: the
        // next turn on another model continues the row, which keeps that model.
        let changed = try ConversationDestination(baseURL: dest.baseURL, model: "other", credentialAccount: dest.credentialAccount)
        let third = try ArchivedConversation(id: first.id, destination: changed, updatedAt: Date(),
            turns: next.turns + [.init(userText: "On the other model", assistantText: "Third actual answer")])
        try state.save(third)
        try a.check(state.conversations[0].destination == changed && state.conversations[0].turns.count == 3,
                    "another model continues the conversation and the row keeps the latest one")
        let before = state
        try a.rejects("old prefix cannot overwrite") { try state.save(first) }
        try a.check(state == before, "stale failure transactional")
        try a.check(dest != ConversationDestination(baseURL: dest.baseURL, model: dest.model, credentialAccount: UUID()), "credential generation is identity")
        try state.delete(id: first.id); try a.check(state.conversations.isEmpty, "delete removes complete record")
        try a.rejects("second delete is stale") { try state.delete(id: first.id) }
        return a.count
    }

    static func malformedState() throws -> Int {
        var a = Assertions(); let dest = try destination(); var state = ConversationArchive(); try state.save(row(destination: dest))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        for field in ["version", "conversations"] {
            var bad = json; bad.removeValue(forKey: field)
            try a.rejects("required archive field " + field) { _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: bad)) }
        }
        for value: Any in [7, "1", NSNull()] {
            var bad = json; bad["version"] = value
            try a.rejects("unknown/malformed version") { _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: bad)) }
        }
        let rows = json["conversations"] as! [[String: Any]]
        var duplicate = json; duplicate["conversations"] = rows + rows
        try a.rejects("duplicate conversation IDs") { _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: duplicate)) }
        for field in ["turns", "destination", "id", "updatedAt"] {
            var badRow = rows[0]; badRow.removeValue(forKey: field); var bad = json; bad["conversations"] = [badRow]
            try a.rejects("required record " + field) { _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: bad)) }
        }
        var badRow = rows[0]; badRow["turns"] = [Any](); var bad = json; bad["conversations"] = [badRow]
        try a.rejects("empty record cannot crash title") { _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: bad)) }
        for url in ["http://example.invalid", "https://user:secret@example.invalid", "https://example.invalid/?key=x", "https://example.invalid/#x"] {
            try a.rejects("unsafe identity URL") { _ = try ConversationDestination(baseURL: url, model: "fixture", credentialAccount: UUID()) }
        }
        try a.rejects("empty response") { _ = try ArchivedConversationTurn(userText: "request", assistantText: " \n") }
        let id = UUID()
        try a.rejects("duplicate message IDs") { _ = try ArchivedConversationTurn(userID: id, assistantID: id, userText: "x", assistantText: "y") }
        try a.rejects("nonfinite date") { _ = try ArchivedConversation(id: UUID(), destination: dest, updatedAt: Date(timeIntervalSinceReferenceDate: .infinity), turns: state.conversations[0].turns) }
        return a.count
    }

    /// Like the Play build saving never stops for lack of room: the oldest
    /// conversations that are not pinned give way. 200 conversations, 1000
    /// turns each and 8 MiB keep the one encrypted file quick to rewrite.
    static func boundedTransactions() throws -> Int {
        var a = Assertions(); let dest = try destination(); var state = ConversationArchive()
        try a.check(ConversationArchive.maximumConversations == 200 && ConversationArchive.maximumTurnsPerConversation == 1000
                    && ConversationArchive.maximumEncodedBytes == 8 * 1024 * 1024, "archive bounds")
        let start = Date(timeIntervalSince1970: 1_000)
        var rows: [ArchivedConversation] = []
        for n in 0..<ConversationArchive.maximumConversations {
            let next = try ArchivedConversation(id: UUID(), destination: dest, updatedAt: start.addingTimeInterval(Double(n)),
                                                turns: [.init(userText: "u\(n)", assistantText: "a")])
            try state.save(next); rows.append(next)
        }
        try state.setPinned(id: rows[0].id, expectedPinnedAt: nil, pinned: true, at: start)
        let newest = try ArchivedConversation(id: UUID(), destination: dest, updatedAt: start.addingTimeInterval(10_000),
                                              turns: [.init(userText: "newest", assistantText: "a")])
        let evicted = try state.save(newest)
        try a.check(evicted == [rows[1].id] && state.conversations.count == ConversationArchive.maximumConversations
                    && state.conversations.contains { $0.id == rows[0].id } && state.conversations.contains { $0.id == newest.id },
                    "a full archive makes room: the oldest unpinned conversation gives way, never a pinned one")
        let turns = try (0..<ConversationArchive.maximumTurnsPerConversation).map { _ in try ArchivedConversationTurn(userText: "u", assistantText: "a") }
        _ = try row(destination: dest, turns: turns); try a.check(turns.count == 1000, "maximum complete turns accepted")
        try a.rejects("turn overflow") { _ = try row(destination: dest, turns: turns + [.init(userText: "u", assistantText: "a")]) }
        try a.rejects("UTF8 overlength") { _ = try ArchivedConversationTurn(userText: String(repeating: "界", count: 349526), assistantText: "a") }
        var bytes = ConversationArchive()
        let half = String(repeating: "y", count: 700_000)
        let older = try ArchivedConversation(id: UUID(), destination: dest, updatedAt: start,
            turns: try (0..<3).map { _ in try ArchivedConversationTurn(userText: half, assistantText: half) })
        try bytes.save(older)
        let newer = try ArchivedConversation(id: UUID(), destination: dest, updatedAt: start.addingTimeInterval(1),
            turns: try (0..<3).map { _ in try ArchivedConversationTurn(userText: half, assistantText: half) })
        let gaveWay = try bytes.save(newer)
        try a.check(gaveWay == [older.id] && bytes.conversations.map(\.id) == [newer.id],
                    "the byte bound makes room the same way")
        var large = ConversationArchive()
        let text = String(repeating: "x", count: 900_000)
        let bigTurns = try (0..<5).map { _ in try ArchivedConversationTurn(userText: text, assistantText: text) }
        try a.rejects("one conversation beyond the byte bound, with nothing to give way") { try large.save(row(destination: dest, turns: bigTurns)) }
        try a.check(large.conversations.isEmpty, "byte overflow unchanged")
        let shared = try ArchivedConversationTurn(userText: "u", assistantText: "a")
        try a.rejects("same pair repeated in one record") { _ = try row(destination: dest, turns: [shared, shared]) }
        var ids = ConversationArchive(); try ids.save(row(destination: dest, turns: [shared])); let oldIDs = ids
        try a.rejects("message IDs cannot cross conversations") { try ids.save(row(destination: dest, turns: [shared])) }
        try a.check(ids == oldIDs, "cross conversation collision unchanged")
        return a.count
    }

    static func renameMigrationAndLateAppend() throws -> Int {
        var a = Assertions(); let dest = try destination(); let first = try row(destination: dest)
        var archive = ConversationArchive(); try archive.save(first)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any]
        legacy["version"] = 1
        let oldest = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        try a.check(oldest.conversations[0].turns == first.turns && oldest.conversations[0].customTitle == nil,
                    "v1 complete messages survive metadata migration")
        legacy["version"] = 2
        archive = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        try a.check(archive.conversations[0].title == String(first.turns[0].userText.prefix(60))
                    && archive.conversations[0].customTitle == nil, "v2 title derives from first message")
        let before = archive.conversations[0]
        try archive.rename(id: first.id, expectedTitle: nil, to: "  我的對話  ")
        let renamed = archive.conversations[0]
        try a.check(renamed.title == "我的對話" && renamed.customTitle == "我的對話"
                    && renamed.turns == before.turns && renamed.destination == before.destination
                    && renamed.updatedAt == before.updatedAt, "rename changes only encrypted display metadata")
        let encoded = try JSONEncoder().encode(archive)
        try a.check(try JSONDecoder().decode(ConversationArchive.self, from: encoded) == archive,
                    "renamed v3 archive survives exact roundtrip")
        let appended = try ArchivedConversation(id: first.id, destination: dest, updatedAt: Date(),
            turns: first.turns + [.init(userText: "Continued request", assistantText: "Continued reply")])
        try archive.save(appended)
        try a.check(archive.conversations[0].title == "我的對話" && archive.conversations[0].turns.count == 2,
                    "late completed pair cannot overwrite a user title")
        let stable = archive
        for invalid in [" ", "Line\nBreak", "Line\u{2028}Break", "Line\u{2029}Break",
                        String(repeating: "界", count: 121),
                        String(repeating: "🙂", count: 121),
                        String(repeating: "e\u{301}\u{301}", count: 120), "A\u{0000}B"] {
            try a.rejects("invalid or oversized title") {
                try archive.rename(id: first.id, expectedTitle: "我的對話", to: invalid)
            }
            try a.check(archive == stable, "invalid title leaves transcript and title unchanged")
        }
        try a.rejects("stale title review") { try archive.rename(id: first.id, expectedTitle: nil, to: "Other") }
        try a.check(archive == stable, "stale rename cannot overwrite newer title")
        try archive.delete(id: first.id)
        try a.rejects("deleted row rename") { try archive.rename(id: first.id, expectedTitle: "我的對話", to: "Other") }
        var malformed = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var rows = malformed["conversations"] as! [[String: Any]]
        rows[0]["customTitle"] = "Invalid\nTitle"; malformed["conversations"] = rows
        try a.rejects("invalid encrypted title on decode") {
            _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: malformed))
        }
        malformed["version"] = 2
        rows[0]["customTitle"] = "Valid title"; malformed["conversations"] = rows
        try a.rejects("v2 cannot claim v3 title metadata") {
            _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: malformed))
        }
        return a.count
    }

    static func pinMigrationOrderingAndCapacity() throws -> Int {
        var a = Assertions(); let dest = try destination()
        func conversation(_ text: String, at seconds: TimeInterval) throws -> ArchivedConversation {
            try .init(id: UUID(), destination: dest, updatedAt: Date(timeIntervalSince1970: seconds),
                      turns: [.init(userText: text, assistantText: "Answer to " + text)])
        }
        func version(_ archive: ConversationArchive) throws -> Int {
            (try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any])["version"] as! Int
        }
        let oldest = try conversation("oldest", at: 100)
        let middle = try conversation("middle", at: 200)
        let newest = try conversation("newest", at: 300)
        var archive = ConversationArchive()
        for record in [oldest, middle, newest] { try archive.save(record) }
        try a.check(try version(archive) == 2
                    && archive.drawerConversations.map(\.id) == [newest.id, middle.id, oldest.id],
                    "old unpinned conversations retain recent order and v2")
        let original = archive.conversations
        let firstPin = Date(timeIntervalSince1970: 1_000)
        let secondPin = Date(timeIntervalSince1970: 1_001)
        try archive.setPinned(id: oldest.id, expectedPinnedAt: nil, pinned: true, at: firstPin)
        try a.check(try version(archive) == 4
                    && archive.drawerConversations.map(\.id) == [oldest.id, newest.id, middle.id]
                    && archive.conversations.first(where: { $0.id == oldest.id })?.updatedAt == oldest.updatedAt
                    && archive.conversations.first(where: { $0.id == oldest.id })?.turns == oldest.turns,
                    "first pin upgrades v4 and changes only display ordering")
        let pinnedOnce = archive
        let pinnedBytes = try JSONEncoder().encode(pinnedOnce)
        var forgedV3 = try JSONSerialization.jsonObject(with: pinnedBytes) as! [String: Any]
        forgedV3["version"] = 3
        try a.rejects("v3 cannot silently ignore pin metadata") {
            _ = try JSONDecoder().decode(ConversationArchive.self,
                from: JSONSerialization.data(withJSONObject: forgedV3))
        }
        var fresh = ConversationArchive()
        let alreadyPinned = pinnedOnce.conversations.first(where: { $0.id == oldest.id })!
        try a.rejects("new model row cannot inject pin metadata") { try fresh.save(alreadyPinned) }
        try a.check(fresh.conversations.isEmpty && (try version(fresh)) == 2,
                    "rejected imported pin cannot upgrade or populate an empty archive")
        try a.rejects("stale second pin cannot overwrite user action") {
            try archive.setPinned(id: oldest.id, expectedPinnedAt: nil, pinned: true, at: secondPin)
        }
        try a.check(archive == pinnedOnce, "stale pin is transactionally unchanged")
        try a.rejects("nonfinite pin time") {
            try archive.setPinned(id: newest.id, expectedPinnedAt: nil, pinned: true,
                                  at: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        try a.check(archive == pinnedOnce, "invalid pin time cannot mutate transcript")
        var pinOnlyV2 = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pinnedOnce)) as! [String: Any]
        pinOnlyV2["version"] = 2
        try a.rejects("v2 cannot claim a pin even without a custom title") {
            _ = try JSONDecoder().decode(ConversationArchive.self,
                from: JSONSerialization.data(withJSONObject: pinOnlyV2))
        }
        try archive.setPinned(id: middle.id, expectedPinnedAt: nil, pinned: true, at: secondPin)
        try a.check(archive.drawerConversations.map(\.id) == [middle.id, oldest.id, newest.id],
                    "more recently pinned row precedes older pin regardless of updatedAt")
        var tied = archive
        try tied.setPinned(id: newest.id, expectedPinnedAt: nil, pinned: true, at: firstPin)
        let tiedIDs = [oldest.id, newest.id].sorted { $0.uuidString < $1.uuidString }
        try a.check(tied.drawerConversations.map(\.id) == [middle.id] + tiedIDs
                    && (try JSONDecoder().decode(ConversationArchive.self,
                        from: JSONEncoder().encode(tied))).drawerConversations.map(\.id) == [middle.id] + tiedIDs,
                    "equal pin times use a stable identity tie break across reload")
        try archive.rename(id: oldest.id, expectedTitle: nil, to: "Renamed and pinned")
        let pinned = archive.conversations.first(where: { $0.id == oldest.id })!
        try a.check(try version(archive) == 4 && pinned.pinnedAt == firstPin && pinned.updatedAt == oldest.updatedAt
                    && pinned.turns == oldest.turns && pinned.title == "Renamed and pinned",
                    "rename retains v4, pin, activity time and exact completed turns")
        let appended = try ArchivedConversation(id: oldest.id, destination: dest, updatedAt: Date(timeIntervalSince1970: 400),
            turns: oldest.turns + [.init(userText: "Continued", assistantText: "Completed")])
        try archive.save(appended)
        let continued = archive.conversations.first(where: { $0.id == oldest.id })!
        try a.check(continued.pinnedAt == firstPin && continued.customTitle == "Renamed and pinned"
                    && continued.turns == appended.turns && continued.updatedAt == appended.updatedAt,
                    "model append preserves both independent user metadata fields")
        let encoded = try JSONEncoder().encode(archive)
        let reopened = try JSONDecoder().decode(ConversationArchive.self, from: encoded)
        try a.check(reopened == archive && reopened.drawerConversations.map(\.id) == archive.drawerConversations.map(\.id)
                    && (try version(reopened)) == 4,
                    "reading and rewriting a v4 archive retains its version and ordering")
        var ordinaryOnV4 = reopened
        try ordinaryOnV4.save(conversation("ordinary after v4", at: 450))
        try a.check(try version(ordinaryOnV4) == 4,
                    "adding an ordinary non-branch conversation to v4 does not upgrade to v5")
        var forgedV2 = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        forgedV2["version"] = 2
        try a.rejects("v2 must reject title and pin metadata") {
            _ = try JSONDecoder().decode(ConversationArchive.self,
                from: JSONSerialization.data(withJSONObject: forgedV2))
        }
        try archive.setPinned(id: middle.id, expectedPinnedAt: secondPin, pinned: false)
        try a.check(archive.drawerConversations.map(\.id) == [oldest.id, newest.id, middle.id]
                    && archive.conversations.first(where: { $0.id == middle.id })?.updatedAt == middle.updatedAt,
                    "unpin restores ordinary recent order without changing activity time")
        let afterUnpin = archive
        try a.rejects("stale unpin cannot erase newer metadata") {
            try archive.setPinned(id: middle.id, expectedPinnedAt: secondPin, pinned: false)
        }
        try a.check(archive == afterUnpin, "stale unpin leaves archive unchanged")
        try archive.setPinned(id: oldest.id, expectedPinnedAt: firstPin, pinned: false)
        try a.check(try version(archive) == 4 && archive.conversations.allSatisfy({ $0.pinnedAt == nil })
                    && archive.drawerConversations.map(\.id) == [oldest.id, newest.id, middle.id],
                    "last unpin keeps v4 protection and latest completed-turn order")
        try archive.rename(id: middle.id, expectedTitle: nil, to: "After unpin")
        try a.check(try version(archive) == 4 && archive.conversations.first(where: { $0.id == middle.id })?.title == "After unpin",
                    "renaming after unpin cannot downgrade v4 to v3")
        for id in [oldest.id, middle.id, newest.id] { try archive.delete(id: id) }
        try a.check(try version(archive) == 4 && archive.conversations.isEmpty,
                    "removing all metadata rows cannot downgrade prior v4 archive")
        try a.check(original.allSatisfy({ $0.pinnedAt == nil && $0.customTitle == nil }),
                    "old row snapshots remain untouched")
        var pinOnly = ConversationArchive(); try pinOnly.save(oldest)
        try pinOnly.setPinned(id: oldest.id, expectedPinnedAt: nil, pinned: true, at: firstPin)
        try pinOnly.setPinned(id: oldest.id, expectedPinnedAt: firstPin, pinned: false)
        try a.check(try version(pinOnly) == 4 && pinOnly.conversations[0].customTitle == nil
                    && pinOnly.conversations[0].pinnedAt == nil
                    && (try JSONDecoder().decode(ConversationArchive.self, from: JSONEncoder().encode(pinOnly))) == pinOnly,
                    "a pin then cancellation cannot downgrade titleless v4 to v2 or v3")

        // Fill the encrypted snapshot to within a few bytes of its bound.
        // A pin must fail rather than evict turns or publish v4 without bytes.
        func nearLimit(_ length: Int) throws -> ConversationArchive {
            let text = String(repeating: "x", count: length)
            let turns = try (0..<5).map { _ in try ArchivedConversationTurn(userText: text, assistantText: text) }
            var result = ConversationArchive()
            try result.save(try conversationWithTurns(turns))
            return result
        }
        func conversationWithTurns(_ turns: [ArchivedConversationTurn]) throws -> ArchivedConversation {
            try .init(id: UUID(), destination: dest, updatedAt: Date(timeIntervalSince1970: 100), turns: turns)
        }
        let seed = try nearLimit(800_000)
        let seedBytes = try JSONEncoder().encode(seed).count
        let extra = (ConversationArchive.maximumEncodedBytes - seedBytes - 8) / 10
        var almostFull = try nearLimit(800_000 + extra)
        let remaining = ConversationArchive.maximumEncodedBytes - (try JSONEncoder().encode(almostFull).count)
        try a.check((4...20).contains(remaining), "fixture has only a few spare encoded bytes")
        let beforeFailure = almostFull
        let fullID = almostFull.conversations[0].id
        do {
            try almostFull.setPinned(id: fullID, expectedPinnedAt: nil, pinned: true, at: firstPin)
            throw Failure(name: "pin at byte bound must fail")
        } catch ConversationArchiveError.full { a.count += 1 }
        try a.check(almostFull == beforeFailure && almostFull.conversations[0].pinnedAt == nil
                    && (try version(almostFull)) == 2,
                    "capacity rejection leaves content, metadata and v2 bytes unchanged")
        return a.count
    }

    static func quoteAndBranch() throws -> Int {
        var a = Assertions()
        let quote = ConversationQuote.Quote(source: .assistant, text: " 明天\n\n下午 ")
        let composed = ConversationQuote.compose(quote, words: "怎麼辦")
        try a.check(composed == "> [Quoting your earlier reply]\n> 明天\n>\n> 下午\n\n怎麼辦",
                    "assistant quote matches Android's wire format")
        let parsed = ConversationQuote.parse(composed)
        try a.check(parsed.quote == .init(source: .assistant, text: "明天\n\n下午") && parsed.words == "怎麼辦",
                    "quoted blank lines and user words round-trip")
        let own = ConversationQuote.compose(.init(source: .user, text: "原話"), words: "重寫")
        try a.check(own == "> [Quoting my earlier message]\n> 原話\n\n重寫"
                    && ConversationQuote.parse(own).quote?.source == .user, "own quote identifies its author")
        try a.check(ConversationQuote.textForSend(quote, words: " \n") == nil
                    && ConversationQuote.textForSend(quote, words: "  問題  ") == ConversationQuote.compose(quote, words: "問題"),
                    "quote alone cannot start a text-only send")
        let old = "> ordinary quote\nkeep spacing  "
        try a.check(ConversationQuote.parse(old).quote == nil && ConversationQuote.parse(old).words == old,
                    "unmarked legacy text remains byte-for-byte unchanged")
        let windows = ConversationQuote.parse("> [Quoting my earlier message]\r\n> one\r\n> two\r\n\r\nnext")
        try a.check(windows.quote?.text == "one\ntwo" && windows.words == "next", "CRLF quote parses")
        try a.check(ConversationQuote.compose(.init(source: .user, text: " "), words: "a") == "a",
                    "empty quote leaves words unchanged")
        try a.check(ConversationQuote.clip(String(repeating: "x", count: 1002)) == String(repeating: "x", count: 1000) + "…",
                    "quote is clipped at Android's 1000 UTF-16 unit bound")
        let emoji = String(repeating: "x", count: 999) + "😀" + "z"
        try a.check(ConversationQuote.clip(emoji) == String(repeating: "x", count: 999) + "…",
                    "clip cannot split a surrogate pair")
        let exact = String(repeating: "😀", count: 500)
        try a.check(ConversationQuote.clip(exact) == exact, "1000 UTF-16 units remain intact")

        let dest = try destination()
        let pdf = try ArchivedPDFAnswer(filename: "fixture.pdf", inputSHA256: String(repeating: "a", count: 64),
            originalPageCount: 1, pages: [.init(number: 1, text: "proof")],
            citations: [.init(readID: UUID(), pageIndex: 1, readOffset: 0, readLength: 5, offset: 0, quote: "proof")])
        let turns = try [ArchivedConversationTurn(userText: composed, assistantText: "First", pdf: pdf),
                         ArchivedConversationTurn(userText: "Second", assistantText: "Second answer"),
                         ArchivedConversationTurn(userText: "Later", assistantText: "Must not copy")]
        let original = try row(destination: dest, turns: turns)
        var archive = ConversationArchive(); try archive.save(original)
        try archive.rename(id: original.id, expectedTitle: nil, to: "Source")
        try archive.setPinned(id: original.id, expectedPinnedAt: nil, pinned: true)
        let source = archive.conversations[0]
        let originalArchive = archive
        let target = UUID(), time = Date(timeIntervalSince1970: 200)
        func prepare(_ id: UUID, busy: Bool = false, unfinished: Bool = false, targetID: UUID = target) throws -> ConversationBranchPlan {
            try .prepare(in: archive, source: source, assistantID: id, targetID: targetID,
                         title: "Source · 分支", at: time, isBusy: busy, hasUnfinishedOrUnsavedTurn: unfinished)
        }
        func rejectsBranch(_ expected: ConversationBranchError, _ name: String, _ body: () throws -> Void) throws {
            do { try body() }
            catch let error as ConversationBranchError where error == expected { a.count += 1; return }
            catch { throw Failure(name: name + " (unexpected error: \(error))") }
            throw Failure(name: name)
        }
        let plan = try prepare(turns[1].assistantID)
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any])["version"] as? Int == 4,
                    "preparing a branch does not write origin or upgrade the source archive")
        try a.check(plan.parentTurn == 1 && plan.source == source && plan.branch.id == target && plan.branch.destination == dest,
                    "branch identifies its source, selected completed turn and destination")
        try a.check(plan.branch.turns.count == 2 && plan.branch.turns.map(\.userText) == turns.prefix(2).map(\.userText)
                    && plan.branch.turns.map(\.assistantText) == turns.prefix(2).map(\.assistantText)
                    && plan.branch.turns[0].pdf == pdf, "branch copies exact completed prefix and PDF evidence")
        let oldIDs = Set(turns.flatMap { [$0.userID, $0.assistantID] })
        let copiedIDs = plan.branch.turns.flatMap { [$0.userID, $0.assistantID] }
        try a.check(Set(copiedIDs).count == copiedIDs.count && oldIDs.isDisjoint(with: copiedIDs),
                    "new messages have distinct IDs throughout the archive")
        try a.check(archive == originalArchive, "preparation never changes the source")
        let result = try plan.applying(to: archive, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        let branched = result.conversations.first { $0.id == target }!
        try a.check(result.conversations.first { $0.id == source.id } == source && source.pinnedAt != nil,
                    "source transcript, title, pin and activity are unchanged")
        try a.check(branched.turns == plan.branch.turns && branched.customTitle == "Source · 分支" && branched.pinnedAt == nil,
                    "branch has its own title and does not inherit the pin")
        let resultBytes = try JSONEncoder().encode(result)
        try a.check(try JSONDecoder().decode(ConversationArchive.self, from: resultBytes) == result,
                    "branch snapshot survives archive serialization")
        try a.check(branched.branchOrigin?.parentID == source.id && branched.branchOrigin?.parentTurn == 1,
                    "branch origin survives with the selected parent and turn")
        var forged = try JSONSerialization.jsonObject(with: resultBytes) as! [String: Any]
        try a.check(forged["version"] as? Int == 5, "branch origin upgrades archive to v5")
        forged["version"] = 4
        try a.rejects("v4 must not silently accept v5 branch origin") {
            _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: forged))
        }
        var changedBranch = result
        try changedBranch.setPinned(id: target, expectedPinnedAt: nil, pinned: true, at: time)
        let pin = changedBranch.conversations.first { $0.id == target }!.pinnedAt
        try changedBranch.setPinned(id: target, expectedPinnedAt: pin, pinned: false)
        try changedBranch.rename(id: target, expectedTitle: branched.customTitle, to: "Renamed branch")
        try changedBranch.delete(id: source.id)
        try a.check(changedBranch.conversations[0].branchOrigin == branched.branchOrigin
                    && (try JSONSerialization.jsonObject(with: JSONEncoder().encode(changedBranch)) as! [String: Any])["version"] as? Int == 5,
                    "pin, rename and parent deletion preserve origin and never downgrade v5")
        try changedBranch.delete(id: target)
        try a.check((try JSONSerialization.jsonObject(with: JSONEncoder().encode(changedBranch)) as! [String: Any])["version"] as? Int == 5,
                    "deleting last branch never downgrades the archive")
        try rejectsBranch(.invalidSelection, "user ID is not an assistant branch point") { _ = try prepare(turns[1].userID) }
        try rejectsBranch(.invalidSelection, "unknown or unfinished preview ID is not an archived turn") { _ = try prepare(UUID()) }
        try rejectsBranch(.blocked, "busy conversation cannot prepare branch") { _ = try prepare(turns[0].assistantID, busy: true) }
        try rejectsBranch(.unfinishedTurn, "unfinished or unsaved conversation cannot prepare branch") { _ = try prepare(turns[0].assistantID, unfinished: true) }
        try rejectsBranch(.invalidTarget, "source ID cannot be reused") { _ = try prepare(turns[0].assistantID, targetID: source.id) }
        try rejectsBranch(.blocked, "busy after preparation cannot apply") { _ = try plan.applying(to: archive, isBusy: true, hasUnfinishedOrUnsavedTurn: false) }
        try rejectsBranch(.unfinishedTurn, "unfinished after preparation cannot apply") { _ = try plan.applying(to: archive, isBusy: false, hasUnfinishedOrUnsavedTurn: true) }
        try rejectsBranch(.invalidTarget, "existing target cannot be overwritten") { _ = try plan.applying(to: result, isBusy: false, hasUnfinishedOrUnsavedTurn: false) }
        var renamed = archive
        try renamed.rename(id: source.id, expectedTitle: source.customTitle, to: "New name")
        try rejectsBranch(.staleSource, "changed source cannot be branched from stale snapshot") { _ = try plan.applying(to: renamed, isBusy: false, hasUnfinishedOrUnsavedTurn: false) }
        var deleted = archive; try deleted.delete(id: source.id)
        try rejectsBranch(.staleSource, "deleted source cannot be revived") { _ = try plan.applying(to: deleted, isBusy: false, hasUnfinishedOrUnsavedTurn: false) }
        try a.check(archive == originalArchive, "all rejected operations leave original archive unchanged")
        var full = archive
        for n in 1..<ConversationArchive.maximumConversations {
            try full.save(row(destination: dest, turns: [.init(userText: "Q\(n)", assistantText: "A")]))
        }
        let others = full.conversations.filter { $0.id != source.id }
        guard let oldest = others.min(by: { $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt })
        else { throw Failure(name: "capacity fixture") }
        let roomPlan = try ConversationBranchPlan.prepare(in: full, source: source, assistantID: turns[0].assistantID,
            targetID: UUID(), title: "Branch", at: time, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        let made = try roomPlan.applying(to: full, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        try a.check(made.conversations.count == ConversationArchive.maximumConversations
                    && made.conversations.contains { $0.id == source.id } && made.conversations.contains { $0.id == roomPlan.branch.id }
                    && !made.conversations.contains { $0.id == oldest.id },
                    "a branch at capacity makes room: the oldest unpinned conversation gives way, never its source")
        return a.count
    }

    /// Like the Play build a turn that did not finish (沒有完成, 已停止。) stays in
    /// its conversation; it needs the v6 archive and a branch keeps it as it was.
    static func failedAndStoppedTurns() throws -> Int {
        var a = Assertions(); let dest = try destination()
        func version(_ archive: ConversationArchive) throws -> Int? {
            (try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])?["version"] as? Int
        }
        let turns = [try ArchivedConversationTurn(userText: "Q", assistantText: "A"),
                     try ArchivedConversationTurn(userText: "Failed", assistantText: "呼叫模型失敗：請求太頻繁，請稍後再試。", outcome: .failed),
                     try ArchivedConversationTurn(userText: "Stopped", assistantText: "已取消", outcome: .cancelled)]
        var plain = ConversationArchive(); try plain.save(try row(destination: dest, turns: [turns[0]]))
        try a.check(try version(plain) == 2, "answers alone keep the v2 encoding")
        let record = try row(destination: dest, turns: turns)
        var archive = ConversationArchive(); try archive.save(record)
        let bytes = try JSONEncoder().encode(archive)
        try a.check(try version(archive) == 6 && (try JSONDecoder().decode(ConversationArchive.self, from: bytes)) == archive,
                    "failed and stopped turns upgrade to v6 and round-trip")
        try a.check(archive.conversations[0].turns.map(\.outcome) == [nil, .failed, .cancelled], "outcomes survive")
        var forged = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        forged["version"] = 5
        try a.rejects("v5 cannot carry failed or stopped turns") {
            _ = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: forged))
        }
        let plan = try ConversationBranchPlan.prepare(in: archive, source: record, assistantID: turns[2].assistantID,
            targetID: UUID(), title: "Branch", at: Date(timeIntervalSince1970: 200), isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        try a.check(plan.branch.turns.map(\.outcome) == [nil, .failed, .cancelled]
                    && plan.branch.turns.map(\.assistantText) == turns.map(\.assistantText),
                    "a branch copies 沒有完成 and 已停止。 as they were")
        let branched = try plan.applying(to: archive, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        try a.check(try version(branched) == 6, "the branch keeps v6")
        try archive.delete(id: record.id)
        try a.check(try version(archive) == 6, "v6 never downgrades")
        return a.count
    }

}

#if CONVERSATION_ARCHIVE_STANDALONE
@main enum ConversationArchiveMain {
    static func main() throws {
        let groups = try [ConversationArchiveChecks.roundTripAndIdentity(), ConversationArchiveChecks.malformedState(),
                          ConversationArchiveChecks.boundedTransactions(), ConversationArchiveChecks.renameMigrationAndLateAppend(),
                          ConversationArchiveChecks.versionCompatibility(),
                          ConversationArchiveChecks.pinMigrationOrderingAndCapacity(), ConversationArchiveChecks.quoteAndBranch(),
                          ConversationArchiveChecks.failedAndStoppedTurns(), ConversationArchiveChecks.independentVaultLocks()]
        print("{\"groups\":9,\"assertions\":\(groups.reduce(0,+))}")
    }
}
#else
import XCTest
final class ConversationArchiveTests: XCTestCase {
    func testIndependentVaultLocks() throws { XCTAssertEqual(try ConversationArchiveChecks.independentVaultLocks(), 1) }
    func testQuoteAndBranch() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.quoteAndBranch(), 0) }
    func testFailedAndStoppedTurns() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.failedAndStoppedTurns(), 0) }
    func testRoundTripAndIdentity() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.roundTripAndIdentity(), 0) }
    func testMalformedState() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.malformedState(), 0) }
    func testBoundedTransactions() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.boundedTransactions(), 0) }
    func testRenameMigrationAndLateAppend() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.renameMigrationAndLateAppend(), 0) }
    func testVersionCompatibility() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.versionCompatibility(), 0) }
    func testPinMigrationOrderingAndCapacity() throws {
        XCTAssertGreaterThan(try ConversationArchiveChecks.pinMigrationOrderingAndCapacity(), 0)
    }
}
#endif
