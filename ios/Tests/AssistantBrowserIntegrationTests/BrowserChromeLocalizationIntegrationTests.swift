import XCTest
@testable import WoowAssistant

@MainActor final class BrowserChromeLocalizationIntegrationTests: XCTestCase {
    func testPackagedStartAndChromeStringsHaveAllThreeLanguages() {
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
            .browserChromeCopyLink, .browserChromeRemoveBookmark, .browserChromeAddBookmark,
            .browserChromeSwitchMobile, .browserChromeSwitchDesktop, .browserChromeDone
        ]
        XCTAssertEqual(messages.count, 52)
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
        let hans = AppLocalizer(language: .simplifiedChinese)
        let english = AppLocalizer(language: .english)
        XCTAssertEqual(hant.text(.browserStartRecent), "最近開啟")
        XCTAssertEqual(hans.text(.browserStartRecent), "最近打开")
        XCTAssertEqual(english.text(.browserStartRecent), "Recently opened")
        XCTAssertEqual(hant.text(.browserChromeHome), "起始頁")
        XCTAssertEqual(hans.text(.browserChromeHome), "起始页")
        XCTAssertEqual(english.text(.browserChromeHome), "Start page")
        XCTAssertEqual(hant.text(.browserPageAskResearch), "問 Mika 研究此網站")
        XCTAssertEqual(hans.text(.browserPageAskResearch), "问 Mika 研究此网站")
        XCTAssertEqual(english.text(.browserPageAskResearch), "Ask Mika to research this site")

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
