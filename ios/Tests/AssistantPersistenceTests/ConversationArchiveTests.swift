import AssistantPersistence
import Foundation

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
    static func row(destination: ConversationDestination, turns: [ArchivedConversationTurn]? = nil) throws -> ArchivedConversation {
        try .init(id: UUID(), destination: destination, updatedAt: Date(timeIntervalSince1970: 100),
                  turns: turns ?? [.init(userText: "Remember this actual request", assistantText: "Completed answer")])
    }

    static func roundTripAndIdentity() throws -> Int {
        var a = Assertions(); var state = ConversationArchive(); let dest = try destination(); let first = try row(destination: dest)
        try state.save(first)
        try a.check(try JSONDecoder().decode(ConversationArchive.self, from: JSONEncoder().encode(state)) == state, "exact Codable roundtrip")
        let next = try ArchivedConversation(id: first.id, destination: dest, updatedAt: Date(),
            turns: first.turns + [.init(userText: "Continue", assistantText: "Second actual answer")])
        try state.save(next); try a.check(state.conversations[0].turns.count == 2, "append retains old pair")
        let before = state
        let changed = try ConversationDestination(baseURL: dest.baseURL, model: "other", credentialAccount: dest.credentialAccount)
        try a.rejects("cross destination replacement") { try state.save(.init(id: first.id, destination: changed, updatedAt: Date(), turns: next.turns)) }
        try a.check(state == before, "destination failure transactional")
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
        for value: Any in [4, "1", NSNull()] {
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

    static func boundedTransactions() throws -> Int {
        var a = Assertions(); let dest = try destination(); var state = ConversationArchive()
        for _ in 0..<ConversationArchive.maximumConversations { try state.save(row(destination: dest)) }
        let before = state
        try a.rejects("full archive never evicts") { try state.save(row(destination: dest)) }
        try a.check(state == before, "full archive unchanged")
        let turns = try (0..<ConversationArchive.maximumTurnsPerConversation).map { _ in try ArchivedConversationTurn(userText: "u", assistantText: "a") }
        _ = try row(destination: dest, turns: turns); try a.check(turns.count == 200, "maximum complete turns accepted")
        try a.rejects("turn overflow") { _ = try row(destination: dest, turns: turns + [.init(userText: "u", assistantText: "a")]) }
        try a.rejects("UTF8 overlength") { _ = try ArchivedConversationTurn(userText: String(repeating: "界", count: 349526), assistantText: "a") }
        var large = ConversationArchive()
        let text = String(repeating: "x", count: 600_000)
        let bigTurns = try (0..<3).map { _ in try ArchivedConversationTurn(userText: text, assistantText: text) }
        try a.rejects("whole encoded byte bound") { try large.save(row(destination: dest, turns: bigTurns)) }
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
}

#if CONVERSATION_ARCHIVE_STANDALONE
@main enum ConversationArchiveMain {
    static func main() throws {
        let groups = try [ConversationArchiveChecks.roundTripAndIdentity(), ConversationArchiveChecks.malformedState(),
                          ConversationArchiveChecks.boundedTransactions(), ConversationArchiveChecks.renameMigrationAndLateAppend()]
        print("{\"groups\":4,\"assertions\":\(groups.reduce(0,+))}")
    }
}
#else
import XCTest
final class ConversationArchiveTests: XCTestCase {
    func testRoundTripAndIdentity() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.roundTripAndIdentity(), 0) }
    func testMalformedState() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.malformedState(), 0) }
    func testBoundedTransactions() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.boundedTransactions(), 0) }
    func testRenameMigrationAndLateAppend() throws { XCTAssertGreaterThan(try ConversationArchiveChecks.renameMigrationAndLateAppend(), 0) }
}
#endif
