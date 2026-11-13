import XCTest
@testable import WoowAssistant

/// Inspect the actual hosted app bundle. A source table or readable emergency
/// fallback cannot make this packaging acceptance pass.
@MainActor final class AppLanguageIntegrationTests: XCTestCase {
    func testPackagedLanguageTablesAndNativePluralResolution() throws {
        // A Simplified Chinese system has no table of its own (2026-11-13): it reads
        // the Traditional Chinese one.
        let simplifiedSystem = AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(simplifiedSystem, .traditionalChinese)
        let expected: [(AppDisplayLanguage, String, String, String)] = [
            (.traditionalChinese, "語言與外觀", "1 輪", "2 輪"),
            (simplifiedSystem, "語言與外觀", "1 輪", "2 輪"),
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
        let simplifiedTables = Bundle.main.bundleURL.appendingPathComponent("zh-Hans.lproj")
        for table in ["App.strings", "App.stringsdict"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: simplifiedTables.appendingPathComponent(table).path), table)
        }
    }
}
