import Foundation
import AssistantSkills

@MainActor enum LanguageResourceChecks {
    static func run(resourceRoot: URL) throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "LanguageResources", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed += 1
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("language-resources-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func makeBundle(_ name: String, languages: [String], omitKey: String? = nil) throws -> Bundle {
            let url = root.appendingPathComponent(name + ".bundle")
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": "io.woow.language." + name, "CFBundlePackageType": "BNDL", "CFBundleDevelopmentRegion": "zh-Hant"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Info.plist"))
            for language in languages {
                let from = resourceRoot.appendingPathComponent(language + ".lproj")
                let to = url.appendingPathComponent(language + ".lproj")
                try fm.copyItem(at: from, to: to)
                if let omitKey, language == "en" {
                    let path = to.appendingPathComponent("App.strings")
                    var strings = try PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as! [String: String]
                    strings.removeValue(forKey: omitKey)
                    try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0).write(to: path)
                }
            }
            return Bundle(url: url)!
        }
        let bundle = try makeBundle("complete", languages: ["zh-Hant", "en"])
        let expected: [(AppDisplayLanguage, String, String)] = [(.traditionalChinese, "語言與外觀", "輪"), (.english, "Language and appearance", "exchanges")]
        for (language, title, plural) in expected {
            let l = AppLocalizer(language: language, bundle: bundle)
            try check(l.resolve(.languageAppearanceTitle).text == title && !l.resolve(.languageAppearanceTitle).usedFallback, "actual localized bundle title")
            for count in [0, 1, 2, 1001] {
                let rendered = l.resolve(.drawerRecentTurns(count: count))
                let numeral = count == 1001 ? "1,001" : String(count)
                let suffix = language == .english && count == 1 ? "exchange" : plural
                try check(rendered.text == numeral + " " + suffix && !rendered.usedFallback, "native stringsdict plural and explicit locale")
            }
            let external = "%1$@ %n %#@count@ language.appearance.title\n使用者原文 🧋"
            let rendered = l.text(.chatQuotingYou(text: external))
            try check(rendered.contains(external), "parameter is verbatim data, never recursive format/key/markup")
        }
        // No Simplified Chinese table (2026-11-13): a Simplified Chinese system reads the Traditional one.
        let simplifiedSystem = AppLocalizer(language: AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"]), bundle: bundle)
        try check(simplifiedSystem.resolve(.languageAppearanceTitle) == AppLocalizedText(text: "語言與外觀", language: .traditionalChinese, usedFallback: false)
                  && simplifiedSystem.text(.drawerRecentTurns(count: 2)) == "2 輪", "a Simplified Chinese system reads the Traditional Chinese table")
        // Every fixed status and the archive explanation must resolve from each
        // shipped bundle, including after the interface language changes.
        let chatMessages: [AppText] = [.chatStatusMCPWorking, .chatStatusWaiting,
            .chatStatusConfigured, .chatStatusUnconfigured, .chatModelSetupHint,
            .chatFixtureNotice, .drawerDeleteTitle, .drawerDeleteBody(title: "A")]
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language, bundle: bundle)
            for message in chatMessages {
                let rendered = localizer.resolve(message)
                try check(!rendered.usedFallback && rendered.language == language && !rendered.text.isEmpty,
                          "chat and archive text exists in each actual bundle")
            }
        }
        let searchMessages: [AppText] = [.localPDFSearchOpen, .localPDFSearchTitle, .localPDFSearchNotice,
            .localPDFSearchPlaceholder, .localPDFSearchIgnoreASCIICase, .localPDFSearchPatternMode,
            .localPDFSearchPatternHelp, .localPDFSearchPatternInvalid, .localPDFSearchPatternUnsupported,
            .localPDFSearchPatternBudget, .localPDFSearchStop, .localPDFSearchRunning, .localPDFSearchButton, .localPDFSearchInvalid, .localPDFSearchFailed,
            .localPDFSearchEmpty, .localPDFSearchCount(count: 2), .localPDFSearchTruncated(count: 20),
            .localPDFSearchHit(page: 3, index: 1), .localPDFSearchSourceFailed]
        for language in AppDisplayLanguage.allCases {
            let localizer = AppLocalizer(language: language, bundle: bundle)
            for message in searchMessages {
                let resolved = localizer.resolve(message)
                try check(!resolved.usedFallback && resolved.language == language && !resolved.text.isEmpty,
                          "offline PDF search text exists in each actual bundle")
            }
        }
        let searchEnglish = AppLocalizer(language: .english, bundle: bundle)
        let searchTraditional = AppLocalizer(language: .traditionalChinese, bundle: bundle)
        try check(searchEnglish.text(.localPDFSearchCount(count: 2)) == "Matches: 2." &&
                  searchTraditional.text(.localPDFSearchCount(count: 2)) == "找到 2 處。", "search count rerenders in selected language")
        try check(searchEnglish.text(.localPDFSearchTruncated(count: 20)) == "Matches: 20; more matches exist.", "truncation is explicit in English")
        try check(searchEnglish.text(.localPDFSearchHit(page: 3, index: 1)) == "Original page 3 (selection 1)" &&
                  searchTraditional.text(.localPDFSearchHit(page: 3, index: 1)) == "原第 3 頁（選取序號 1）", "original page and occurrence are not interchanged")
        let searchSuite = "io.woow.test.search-language." + UUID().uuidString
        guard let searchDefaults = UserDefaults(suiteName: searchSuite) else { throw NSError(domain: "LanguageResources", code: 2) }
        defer { searchDefaults.removePersistentDomain(forName: searchSuite) }
        // A Simplified Chinese system: following it shows Traditional Chinese.
        let searchStore = AppLanguageStore(defaults: searchDefaults, preferredLanguages: { ["zh-Hans-CN"] })
        for (choice, expected) in [(AppLanguage.english, "Search"), (.system, "搜尋"), (.traditionalChinese, "搜尋")] {
            try check(searchStore.setFromUser(choice), "interface language saved")
            let selected = AppLocalizer(language: searchStore.resolved, bundle: bundle)
            try check(selected.text(.localPDFSearchButton) == expected && !selected.resolve(.localPDFSearchButton).usedFallback,
                      "search follows the language setting")
        }
        try check(AppLocalizer(language: .english, bundle: bundle).text(.chatStatusWaiting) == "Working",
                  "in-flight status uses the current language")
        try check(AppLocalizer(language: .traditionalChinese, bundle: bundle).text(.drawerDeleteBody(title: "A")) == "「A」和裡面的檔案都會刪掉。",
                  "the drawer's delete prompt is formatted with the selected language")
        let en = AppLocalizer(language: .english, bundle: bundle)
        let hant = AppLocalizer(language: .traditionalChinese, bundle: bundle)
        let partial = try makeBundle("partial", languages: ["zh-Hant", "en"], omitKey: "language.appearance.title")
        let fallback = AppLocalizer(language: .english, bundle: partial).resolve(.languageAppearanceTitle)
        try check(fallback.text == "語言與外觀" && fallback.language == .traditionalChinese && fallback.usedFallback, "missing individual key falls back to Hant, not system English")
        let hantOnly = try makeBundle("hantOnly", languages: ["zh-Hant"])
        let missingLanguage = AppLocalizer(language: .english, bundle: hantOnly).resolve(.drawerRecentTurns(count: 2))
        try check(missingLanguage.text == "2 輪" && missingLanguage.usedFallback, "missing language plural falls back to Hant")
        let empty = try makeBundle("empty", languages: [])
        let emergency = AppLocalizer(language: .english, bundle: empty)
        try check(emergency.text(.languageAppearanceTitle) == "語言與外觀" && emergency.resolve(.languageAppearanceTitle).usedFallback, "missing packaged resources preserve readable Hant")
        try check(emergency.text(.drawerRecentTurns(count: 2)) == "2 輪", "missing packaged plural uses typed Hant fallback")
        let searchFallback = try makeBundle("searchPartial", languages: ["zh-Hant", "en"], omitKey: "localPDFSearch.invalid")
        let missingSearch = AppLocalizer(language: .english, bundle: searchFallback).resolve(.localPDFSearchInvalid)
        try check(missingSearch.usedFallback && missingSearch.language == .traditionalChinese &&
                  missingSearch.text == searchTraditional.text(.localPDFSearchInvalid), "missing search error falls back to Traditional Chinese")
        let modelErrors: [ModelSettingsError] = [.invalidURL, .missingModel, .missingKey, .changedOrigin, .invalidKey, .unavailableKeychain,
                                                 .keychainStatus(-25293), .tooManyProviders, .consentRequired]
        for error in modelErrors {
            let message = AppLocalizer.modelSettingsError(error)
            try check(hant.text(message) == error.errorDescription, "model settings code presentation preserves original Hant including ungrouped system code")
            try check(en.text(message) != error.errorDescription && !en.resolve(message).usedFallback, "shared known setting errors have packaged English translations")
        }
        try check(en.text(.modelSettingsKeychainStatus(code: "-25293")).contains("-25293"), "system code is not locale-grouped")
        let uuid = UUID().uuidString
        let suite = try AppLanguagePreferences.suiteName(arguments: ["-UITestMode", "-UITestNamespace", uuid], debug: true)
        try check(suite.hasSuffix(".test." + uuid), "fixture preferences are isolated")
        try check(try AppLanguagePreferences.suiteName(arguments: ["-LiveModelUITest", "-LiveModelUITestNamespace", uuid], debug: true) == suite, "live fixture preferences use explicit namespace")
        for arguments in [["-UITestMode"], ["-UITestNamespace", uuid], ["-UITestMode", "-UITestNamespace", "bad"], ["-UITestMode", "-LiveModelUITest", "-UITestNamespace", uuid], ["-UITestMode", "-UITestNamespace", uuid, "-LiveModelUITestNamespace", uuid], ["-UITestMode", "-UITestMode", "-UITestNamespace", uuid], ["-UITestMode", "-UITestNamespace", uuid, "-UITestNamespace", uuid]] {
            do { _ = try AppLanguagePreferences.suiteName(arguments: arguments, debug: true); try check(false, "invalid namespace accepted") }
            catch AppLanguagePreferences.ConfigurationError.invalidTestNamespace { passed += 1 }
        }
        try check(try AppLanguagePreferences.suiteName(arguments: ["-UITestMode"], debug: false) == AppLanguagePreferences.productionSuite, "Release ignores harness arguments")
        return passed
    }
}
