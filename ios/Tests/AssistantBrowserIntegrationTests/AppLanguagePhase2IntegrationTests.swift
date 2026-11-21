import XCTest
import AssistantDomain
@testable import WoowAssistant

/// Actual packaged tables and native notification request objects. Does not
/// access the notification center, send notifications or grant permissions.
@MainActor final class AppLanguagePhase2IntegrationTests: XCTestCase {
    func testMCPActivityStoredTextMapsRecordAndErrorCountsToEnglish() throws {
        let english = AppLocalizer(language: .english)
        let traditional = AppLocalizer(language: .traditionalChinese)
        let cases: [(String, AppText, String)] = [
            ("MCP 嘗試呼叫 4 次；結果紀錄 4 筆；異常 2 筆。",
             .storedChatMcpActivity(tried: 4, received: 4, failed: 2),
             "MCP calls attempted: 4; result records: 4; errors: 2."),
            ("MCP 嘗試呼叫 3 次；結果紀錄 1 筆；異常 0 筆。",
             .storedChatMcpActivity(tried: 3, received: 1, failed: 0),
             "MCP calls attempted: 3; result records: 1; errors: 0.")
        ]
        for (raw, expectedMessage, expectedEnglish) in cases {
            let parsed = try XCTUnwrap(AppText.storedMessage(raw))
            XCTAssertEqual(parsed, expectedMessage)
            XCTAssertEqual(english.stored(raw), expectedEnglish)
            XCTAssertEqual(traditional.stored(raw), raw)
            let resolved = english.resolve(parsed)
            XCTAssertEqual(resolved.text, expectedEnglish)
            XCTAssertEqual(resolved.language, .english)
            XCTAssertFalse(resolved.usedFallback)
        }
    }

    func testPackagedMCPBrowserCatalogAndNotificationMessagesKeepTypedData() throws {
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            let messages: [AppText] = [.mcpConnecting, .mcpSelectedCount(count: 1), .mcpSelectedCount(count: 2),
                .searchInvalid, .catalogReadyAuthor, .notificationApprovalTitle,
                .mcpKeychainStatus(code: "-25308")]
            for message in messages {
                let actual = localizer.resolve(message)
                XCTAssertFalse(actual.usedFallback)
                XCTAssertEqual(actual.language, language)
                XCTAssertFalse(actual.text.isEmpty)
            }
            let query = "%n catalog.title 原文 %@"
            XCTAssertTrue(localizer.text(.browserHistorySearch(query: query)).hasSuffix(query))
            XCTAssertEqual(localizer.text(.searchTemplate), "https://example.com/search?q=%s")
            let payload = TaskNotificationPayload(kind: .approval, destination: .chat)
            let scope = UUID().uuidString
            let request = TaskNotificationCenterAdapter.request(payload, sound: false, scope: scope, localizer: localizer)
            XCTAssertEqual(request.content.title, localizer.text(.notificationApprovalTitle))
            XCTAssertEqual(request.content.body, localizer.text(.notificationApprovalBody))
            XCTAssertEqual(TaskNotificationCenterAdapter.logicalIdentifier(request.identifier, scope: scope), payload.identifier)
            XCTAssertTrue(request.content.userInfo.isEmpty)
            XCTAssertTrue(request.content.attachments.isEmpty)
            XCTAssertTrue(request.content.categoryIdentifier.isEmpty)
            XCTAssertNil(request.content.sound)
        }
        let english = AppLocalizer(language: .english)
        XCTAssertEqual(english.text(.mcpSelectedCount(count: 1)), "1 tool selected for chat")
        XCTAssertEqual(english.text(.mcpSelectedCount(count: 2)), "2 tools selected for chat")
    }
}
