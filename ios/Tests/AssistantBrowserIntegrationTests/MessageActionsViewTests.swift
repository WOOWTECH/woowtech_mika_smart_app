#if os(iOS) && canImport(XCTest)
import AssistantPersistence
import SwiftUI
import UIKit
import XCTest
@testable import WoowAssistant

final class MessageActionsViewTests: XCTestCase {
    @MainActor func testQuoteChipHostsAtAccessibilityTextSizeInAllLanguages() {
        let messages: [AppText] = [.messageActions, .messageCopy, .messageQuote, .messageBranch,
                                   .messageBranchSuffix, .messageActionFailed, .messageQuoteAssistant,
                                   .messageQuoteUser, .messageQuoteRemove]
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            for message in messages {
                let result = localizer.resolve(message)
                XCTAssertFalse(result.usedFallback, "Missing \(message.key) in \(language.rawValue)")
                XCTAssertEqual(result.language, language)
                XCTAssertFalse(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            for author in [ConversationQuote.Source.assistant, .user] {
                let quote = ConversationQuote.Quote(source: author, text: "First line\nSecond line\nThird line")
                let view = MessageQuoteChip(quote: quote, localizer: localizer, disabled: false, remove: {})
                    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
                let host = UIHostingController(rootView: view)
                host.loadViewIfNeeded()
                let size = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
                XCTAssertGreaterThanOrEqual(size.height, 44)
                XCTAssertLessThan(size.height, 1000)
                XCTAssertLessThanOrEqual(size.width, 320)
                let sent = UIHostingController(rootView: MessageSentQuote(quote: quote, localizer: localizer)
                    .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge))
                sent.loadViewIfNeeded()
                let sentSize = sent.sizeThatFits(in: CGSize(width: 320, height: 1000))
                XCTAssertGreaterThan(sentSize.height, 0)
                XCTAssertLessThan(sentSize.height, 1000)
                XCTAssertLessThanOrEqual(sentSize.width, 320)
            }
        }
    }
}
#endif
