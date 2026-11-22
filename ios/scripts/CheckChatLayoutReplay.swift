import AssistantModels
import AssistantPersistence
import Foundation

@MainActor enum ChatLayoutReplayChecks {
    struct Failure: Error { let name: String }
    static func run() async throws -> Int {
        var assertions = 0
        func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try value() else { throw Failure(name: name) }; assertions += 1
        }
        let sourceID = UUID(), namespace = UUID()
        let flags = ["app", "-WoowLayoutDiagnostics", "-WoowLayoutReplaySource", sourceID.uuidString,
                     "-WoowLayoutReplayNamespace", namespace.uuidString, "-WoowLayoutReplayTurns", "5"]
        try check(try ChatLayoutReplay.Configuration.resolve([]) == nil, "ordinary launch absent")
        let config = try ChatLayoutReplay.Configuration.resolve(flags)!
        try check(config.source == sourceID && config.namespace == namespace && config.turns == 5, "exact configuration")
        for invalid in [Array(flags.dropLast()), flags + ["-WoowLayoutReplayTurns", "5"],
                        flags.filter { $0 != "-WoowLayoutDiagnostics" }, flags + ["-WoowLayoutDiagnostics"],
                        flags + ["-UITestMode"], flags + ["-WoowLayoutReplayUnknown"],
                        Array(flags.dropLast()) + ["0"], Array(flags.dropLast()) + ["26"]] {
            do { _ = try ChatLayoutReplay.Configuration.resolve(invalid); throw Failure(name: "invalid accepted") }
            catch is ChatLayoutReplay.Failure { assertions += 1 }
        }
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("ReplayChecks-" + UUID().uuidString)
        let source = base.appendingPathComponent("source")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        defer {
            try? manager.removeItem(at: base)
            UserDefaults.standard.removePersistentDomain(forName: "io.woowtech.assistant.layout-replay." + namespace.uuidString)
        }
        let itemID = UUID(), relative = sourceID.uuidString + "/" + itemID.uuidString + "/image.png"
        let input = source.appendingPathComponent(relative)
        try manager.createDirectory(at: input.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = Data((0..<4270).map { UInt8($0 % 251) }) // byte-copy fixture, not a rendered image claim
        try bytes.write(to: input)
        let attachment = try ArchivedAttachment(id: itemID, isPhoto: true, name: "image.png",
            byteCount: Int64(bytes.count), relativePath: relative, contentType: "public.png")
        let turns = try (0..<6).map { index in
            try ArchivedConversationTurn(userText: "問題 \(index)", assistantText: "回答 \(index)",
                                         attachments: index == 3 ? [attachment] : [])
        }
        let destination = try ConversationDestination(baseURL: "https://source.example.invalid/v1",
            model: "source", credentialAccount: UUID())
        let original = try ArchivedConversation(id: sourceID, destination: destination, updatedAt: Date(), turns: turns)
        let session = try ChatLayoutReplay.makeIsolatedSession(config, record: original, sourceAttachments: source, base: base)
        try check(session.entries.count == 10 && session.entries[6].attachments.count == 1, "prefix and actual attachment model")
        try check(session.archive?.state.conversations.first?.turns == Array(turns.prefix(5)), "exact historical turns")
        let copied = session.attachmentStore.url(for: session.entries[6].attachments[0])
        try check(copied != input && Data(contentsOf: copied) == bytes, "independent exact bytes")
        session.draft = "請測試本機失敗回覆"
        session.attemptSend()
        try check(session.isSubmitting, "real send path started")
        await session.capturedArchiveRequest?.value
        try check(!session.isSubmitting && session.entries.count == 12, "failure returns and archives")
        try check(session.entries.last?.outcome == .failed && session.entries.last?.content.contains("請求太頻繁") == true,
                  "local HTTP429 presentation")
        try check(try Data(contentsOf: input) == bytes && original.turns.count == 6, "source preserved")
        let fresh = try ChatLayoutReplay.makeIsolatedSession(config, record: original, sourceAttachments: source, base: base)
        try check(fresh.entries.count == 10 && fresh.archive?.state.conversations.first?.turns == Array(turns.prefix(5)),
                  "same namespace restores baseline")
        try check(try Data(contentsOf: fresh.attachmentStore.url(for: fresh.entries[6].attachments[0])) == bytes, "relaunch image bytes")

        var changed = turns
        changed[0] = try ArchivedConversationTurn(userText: "changed", assistantText: "changed")
        let different = try ArchivedConversation(id: sourceID, destination: destination, updatedAt: original.updatedAt, turns: changed)
        do {
            _ = try ChatLayoutReplay.makeIsolatedSession(config, record: different, sourceAttachments: source, base: base)
            throw Failure(name: "changed baseline accepted")
        } catch ChatLayoutReplay.Failure.copyMismatch { assertions += 1 }
        try check(try Data(contentsOf: input) == bytes, "changed baseline never alters source")

        let rootLink = base.appendingPathComponent("root-link")
        try manager.createSymbolicLink(at: rootLink, withDestinationURL: source)
        do {
            try ChatLayoutReplay.copyAttachments(turns, from: rootLink, to: base.appendingPathComponent("refused-root"))
            throw Failure(name: "source root symlink accepted")
        } catch ChatLayoutReplay.Failure.unsafeFile { assertions += 1 }

        try manager.removeItem(at: input)
        try manager.createSymbolicLink(at: input, withDestinationURL: copied)
        do {
            try ChatLayoutReplay.copyAttachments(turns, from: source, to: base.appendingPathComponent("refused"))
            throw Failure(name: "symlink accepted")
        } catch ChatLayoutReplay.Failure.unsafeFile { assertions += 1 }
        let other = UUID(), parent = base.appendingPathComponent("ChatLayoutReplay")
        let marker = source.appendingPathComponent("marker")
        try Data([7]).write(to: marker)
        try manager.createSymbolicLink(at: parent.appendingPathComponent(other.uuidString), withDestinationURL: source)
        do { _ = try ChatLayoutReplay.resetDirectory(other, base: base); throw Failure(name: "reset followed symlink") }
        catch ChatLayoutReplay.Failure.unsafeFile { assertions += 1 }
        try check(try Data(contentsOf: marker) == Data([7]), "reset preserved sibling target")
        return assertions
    }
}
