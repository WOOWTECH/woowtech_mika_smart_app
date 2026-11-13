import XCTest
@testable import WoowAssistant

@MainActor final class BrowserChromeLocalizationIntegrationTests: XCTestCase {
    func testPackagedStartAndChromeStringsHaveBothLanguages() {
        let messages: [AppText] = [
            .browserStartDone, .browserStartEdit, .browserStartRecent, .browserStartClear,
            .browserStartSuggestionHelp, .browserStartAddBookmark, .browserStartViewBookmarks,
            .browserStartOK, .browserStartAddBookmarkHelp, .browserStartRemoveBookmark(name: "Page"),
            .browserStartAdd, .browserStartSuggestionSubtitle,
            .browserChromeClosePage, .browserChromeAddressPlaceholder, .browserChromeClearInput,
            .browserChromeStop, .browserChromeReload, .browserChromeOpen,
            .browserChromeSearchEngine(name: "Engine"),
            .browserChromeSearchMatch(query: "Query", engine: "Engine"),
            .browserChromeAutomationNotice, .browserChromeReturnManual, .browserChromeResearch,
            .browserChromeResearchSite, .browserPageAskResearch, .browserChromeInteract, .browserChromeLibrary,
            .browserChromeExplanation, .browserChromeFind, .browserChromeCurrentDesktop,
            .browserChromeCurrentMobile, .browserChromeMobileWebsite, .browserChromeDesktopWebsite,
            .browserChromeSiteModeHelp, .browserChromeSiteMode, .browserChromeDesktop,
            .browserChromeMobile, .browserChromeMultiResearch, .browserChromeTranscript,
            .browserChromeBack, .browserChromeForward, .browserChromeHome, .browserChromeShare,
            .browserChromeShareUnavailable, .browserChromeMore, .browserChromeWebsite,
            .browserChromeCopyLink, .browserChromeOpenOutside,
            .browserChromeRemoveBookmark, .browserChromeAddBookmark,
            .browserChromeSwitchMobile, .browserChromeSwitchDesktop, .browserChromeDone
        ]
        XCTAssertEqual(messages.count, 53)
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            for message in messages {
                let resolved = localizer.resolve(message)
                XCTAssertEqual(resolved.language, language, message.key)
                XCTAssertFalse(resolved.usedFallback, message.key)
                XCTAssertFalse(resolved.text.isEmpty, message.key)
                XCTAssertTrue(message.key.hasPrefix("browser."), message.key)
            }
        }
    }

    func testLocalizedControlsPreserveStableMeaningAndUntrustedNames() {
        let hant = AppLocalizer(language: .traditionalChinese)
        // A Simplified Chinese system shows the Traditional Chinese words.
        let simplifiedSystem = AppLocalizer(language: AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"]))
        let english = AppLocalizer(language: .english)
        XCTAssertEqual(hant.text(.browserStartRecent), "最近開啟")
        XCTAssertEqual(simplifiedSystem.text(.browserStartRecent), "最近開啟")
        XCTAssertEqual(english.text(.browserStartRecent), "Recently opened")
        XCTAssertEqual(hant.text(.browserChromeHome), "起始頁")
        XCTAssertEqual(simplifiedSystem.text(.browserChromeHome), "起始頁")
        XCTAssertEqual(english.text(.browserChromeHome), "Start page")
        XCTAssertEqual(hant.text(.browserPageAskResearch), "問渥屋助理研究此網站")
        XCTAssertEqual(simplifiedSystem.text(.browserPageAskResearch), "問渥屋助理研究此網站")
        XCTAssertEqual(english.text(.browserPageAskResearch), "Ask the assistant to research this site")
        XCTAssertEqual(hant.text(.browserChromeOpenOutside), "在其他 App 開啟")
        XCTAssertEqual(simplifiedSystem.text(.browserChromeOpenOutside), "在其他 App 開啟")
        XCTAssertEqual(english.text(.browserChromeOpenOutside), "Open in another app")

        let page = "%n browser.start.recent 🧋"
        let query = "%1$@ browser.chrome.search.match"
        let engine = "%s 🧭"
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language)
            let remove = localizer.text(.browserStartRemoveBookmark(name: page))
            XCTAssertEqual(remove.components(separatedBy: page).count, 2)
            let search = localizer.text(.browserChromeSearchMatch(query: query, engine: engine))
            XCTAssertEqual(search.components(separatedBy: query).count, 2)
            XCTAssertEqual(search.components(separatedBy: engine).count, 2)
        }
    }
}
