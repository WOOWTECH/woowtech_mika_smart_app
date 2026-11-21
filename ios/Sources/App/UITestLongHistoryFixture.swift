#if DEBUG
import AssistantPersistence
import Foundation

/// Synthetic rendering workload, not a real conversation or model-service benchmark.
/// The first launch saves through the production encrypted archive store. ChatSession
/// has already loaded its archive when the model repository hook runs, so the UI test
/// must relaunch WITHOUT reset and open the saved row through the real drawer.
@MainActor enum UITestLongHistoryFixture {
    static let flag = "-UITestLongHistoryFixture"
    static let turnsFlag = "-UITestLongHistoryTurns"

    struct Configuration {
        let namespace: UUID
        let turns: Int
        let reset: Bool
    }
    enum Invalid: Error { case arguments, capacity, existingData, missingModel, verification }

    static func resolve(arguments: [String]) throws -> Configuration? {
        guard arguments.contains(where: { $0.hasPrefix("-UITestLongHistory") }) else { return nil }
        let required = [flag, turnsFlag, "-UITestMode", "-UITestNamespace", "-UITestTranscriptFixture"]
        let allowed = required + ["-UITestResetStorage"]
        guard required.allSatisfy({ item in arguments.filter { $0 == item }.count == 1 }),
              arguments.filter({ $0 == "-UITestResetStorage" }).count <= 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              !arguments.contains(where: { $0.hasPrefix("-UITest") && !allowed.contains($0) }),
              let namespaceIndex = arguments.firstIndex(of: "-UITestNamespace"),
              arguments.indices.contains(namespaceIndex + 1),
              let namespace = UUID(uuidString: arguments[namespaceIndex + 1]),
              namespace.uuidString.lowercased() == arguments[namespaceIndex + 1].lowercased(),
              let turnsIndex = arguments.firstIndex(of: turnsFlag), arguments.indices.contains(turnsIndex + 1),
              ["999", "1000"].contains(arguments[turnsIndex + 1]),
              let turns = Int(arguments[turnsIndex + 1]) else { throw Invalid.arguments }
        return Configuration(namespace: namespace, turns: turns, reset: arguments.contains("-UITestResetStorage"))
    }

    static func prepare(_ configuration: Configuration, arguments: [String], repository: ModelSettingsRepository) throws {
        // Normal reopens never reseed or replace an archive, including a newly saved 1000th turn.
        guard configuration.reset else { return }
        let started = ProcessInfo.processInfo.systemUptime
        guard ConversationArchive.maximumTurnsPerConversation == 1000 else { throw Invalid.capacity }
        guard let settings = try repository.load(), let target = settings.accessIdentity?.target else {
            throw Invalid.missingModel
        }
        let location = try ConversationArchiveStore.location(arguments: arguments)
        guard location.reset,
              location.url.deletingLastPathComponent().lastPathComponent == "test-" + configuration.namespace.uuidString,
              location.service == "io.woowtech.assistant.conversations.v1.test-" + configuration.namespace.uuidString
        else { throw Invalid.arguments }
        let vault = EncryptedLearningFile(url: location.url, keys: LearningKeychainStore(service: location.service))
        let store = ConversationArchiveStore(vault: vault)
        guard store.available, store.state.conversations.isEmpty else { throw Invalid.existingData }
        let destination = try ConversationDestination(baseURL: settings.baseURL.absoluteString,
            model: target.model, credentialAccount: target.providerID)
        let turns = try (1...configuration.turns).map { index in
            try ArchivedConversationTurn(userID: messageID(index * 2 - 1), assistantID: messageID(index * 2),
                userText: userText(index: index, turns: configuration.turns), assistantText: assistantText(index: index))
        }
        let record = try ArchivedConversation(id: configuration.namespace, destination: destination,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000), turns: turns)
        let evicted = try store.save(record, expected: nil)
        store.reload()
        guard evicted.isEmpty, store.available, store.state.conversations == [record],
              record.turns.count == configuration.turns,
              record.turns.allSatisfy({ $0.outcome == nil }) else { throw Invalid.verification }
        let encodedBytes = try JSONEncoder().encode(store.state).count
        // Leave room for the production encrypted envelope; never truncate the fixture.
        guard encodedBytes < ConversationArchive.maximumEncodedBytes / 2 else { throw Invalid.capacity }
        let manifest: [String: Any] = [
            "fixture": "long-history-v1", "synthetic": true, "namespace": configuration.namespace.uuidString,
            "turns": turns.count, "messages": turns.count * 2, "tables": turns.count / 100,
            "encodedBytes": encodedBytes, "maximumTurns": ConversationArchive.maximumTurnsPerConversation,
            "maximumArchiveBytes": ConversationArchive.maximumEncodedBytes,
            "seedSeconds": ProcessInfo.processInfo.systemUptime - started,
            "path": "ConversationArchiveStore.save/encrypted/reload"
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        print("LONG_HISTORY_SEED " + String(decoding: data, as: UTF8.self))
    }

    private static func messageID(_ ordinal: Int) -> UUID {
        UUID(uuidString: "10000000-0000-4000-8000-" + String(format: "%012llX", Int64(ordinal)))!
    }

    private static func userText(index: Int, turns: Int) -> String {
        let paragraph = "這是完全合成的中文長歷史測試資料，用來觀察閱讀、鍵盤輸入與完成回覆時的畫面反應。請保留先前討論的背景，逐項整理工作安排與資料核對方式。文字不代表真實使用者、交易、帳戶或待執行的指令，也不需要連線到任何服務。"
        return "LH-SYNTHETIC-\(turns) 第\(index)輪\n\n" + Array(repeating: paragraph, count: 2).joined(separator: "\n\n")
    }

    private static func assistantText(index: Int) -> String {
        let paragraph = "整理這一輪的合成內容時，先列出目前已知的資訊，再檢查各項條件是否一致。較長的中文段落會在不同螢幕寬度下換行，讓測試涵蓋文字排版、歷史訊息載入與捲動位置。所有內容都是固定的測試文字，沒有個人資料，也沒有真實模型產生的研究結論。"
        var result = "LH-ANSWER-\(index)\n\n" + Array(repeating: paragraph, count: 4).joined(separator: "\n\n")
        if index.isMultiple(of: 100) {
            result += "\n\n| 項目 | 狀態 | 數量 |\n| --- | --- | --- |\n| 合成文件 | 已核對 | 12 |\n| 合成段落 | 已整理 | 24 |\n| 合成表格 | 待閱讀 | 3 |"
        }
        return result + "\n\nLH-END-\(index)"
    }
}
#endif
