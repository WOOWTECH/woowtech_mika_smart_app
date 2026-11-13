import XCTest
@testable import WoowAssistant

/// Inspect the actual hosted app bundle. A source table or readable emergency
/// fallback cannot make this packaging acceptance pass.
@MainActor final class AppLanguageIntegrationTests: XCTestCase {
    func testPackagedLanguageTablesAndNativePluralResolution() throws {
        let expected: [(AppDisplayLanguage, String, String, String)] = [
            (.traditionalChinese, "語言與外觀", "1 輪", "2 輪"),
            (.simplifiedChinese, "语言与外观", "1 轮", "2 轮"),
            (.english, "Language and appearance", "1 exchange", "2 exchanges")
        ]
        for (language, title, singular, plural) in expected {
            let directory = try XCTUnwrap(Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("App.strings").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("App.stringsdict").path))
            let localizer = AppLocalizer(language: language)
            for (message, text) in [(AppText.languageAppearanceTitle, title),
                                    (.drawerRecentTurns(count: 1), singular),
                                    (.drawerRecentTurns(count: 2), plural)] {
                let resolved = localizer.resolve(message)
                XCTAssertEqual(resolved.text, text)
                XCTAssertEqual(resolved.language, language)
                XCTAssertFalse(resolved.usedFallback)
            }
            let original = "%n %#@count@ 原文 🧋"
            XCTAssertTrue(localizer.text(.chatQuotingYou(text: original)).contains(original))
            let search: [AppText] = [.localPDFSearchOpen, .localPDFSearchTitle, .localPDFSearchNotice,
                .localPDFSearchPlaceholder, .localPDFSearchButton, .localPDFSearchInvalid, .localPDFSearchFailed,
                .localPDFSearchEmpty, .localPDFSearchCount(count: 2), .localPDFSearchTruncated(count: 20),
                .localPDFSearchHit(page: 3, index: 1), .localPDFSearchSourceFailed]
            for message in search {
                let resolved = localizer.resolve(message)
                XCTAssertEqual(resolved.language, language)
                XCTAssertFalse(resolved.usedFallback)
                XCTAssertFalse(resolved.text.isEmpty)
            }
        }
    }
}
