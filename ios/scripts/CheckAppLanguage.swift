import Foundation
import Combine
import AssistantSkills
@main enum LanguageChecks {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "language-check", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            passed += 1
        }
        // Owner, 2026-11-13: 簡中用繁中跟其他語言用英文. The first system language with
        // an interface decides; Chinese in either script is Traditional Chinese.
        let mappings: [([String], AppDisplayLanguage)] = [
            ([], .english), (["fr-FR", "ja-JP"], .english), (["ja"], .english), (["en-GB"], .english),
            (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese),
            (["zh-MO"], .traditionalChinese), (["zh-Hant"], .traditionalChinese), (["zh-Hant-US"], .traditionalChinese),
            (["zh-Hans"], .traditionalChinese), (["zh-Hans-CN"], .traditionalChinese),
            (["zh-CN"], .traditionalChinese), (["zh-SG"], .traditionalChinese), (["zh_CN"], .traditionalChinese),
            (["zh-Hans-TW"], .traditionalChinese), (["zh-Hans-HK"], .traditionalChinese), (["zh"], .traditionalChinese),
            (["yue-Hant-HK"], .traditionalChinese), (["yue-Hans-CN"], .traditionalChinese),
            (["ja-JP", "zh-TW"], .traditionalChinese), (["ja-JP", "zh-Hans-CN"], .traditionalChinese),
            (["en-US", "zh-TW"], .english), (["zh-CN", "en-US"], .traditionalChinese),
            (["ko-KR", "en-GB", "zh-TW"], .english)]
        for (preferences, expected) in mappings {
            try check(AppLanguage.system.resolve(preferredLanguages: preferences) == expected,
                      "system language matching: \(preferences)")
        }
        for (choice, expected) in [(AppLanguage.traditionalChinese, AppDisplayLanguage.traditionalChinese),
                                   (.simplifiedChinese, .simplifiedChinese), (.english, .english)] {
            for preferences in [[], ["ja-JP"], ["zh-HK"], ["zh-Hans-CN"], ["en-GB"]] {
                try check(choice.resolve(preferredLanguages: preferences) == expected, "explicit selection ignores system language")
            }
        }
        let suite = "woow.language.foundation.check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = ["zh-TW"]
        let language = AppLanguageStore(defaults: defaults, preferredLanguages: { preferences })
        let appearance = SelfConfigurationStore(defaults: defaults)
        try check(language.language == .system && language.resolved == .traditionalChinese, "missing key resolves system")
        try check(defaults.object(forKey: AppLanguageStore.preferenceKey) == nil, "read does not persist a default")
        appearance.setAppearanceFromUser(.dark)
        let before = defaults.persistentDomain(forName: suite)!
        try check(language.setFromUser(.english), "manual language readback")
        let after = defaults.persistentDomain(forName: suite)!.filter { $0.key != AppLanguageStore.preferenceKey }
        try check(NSDictionary(dictionary: before).isEqual(to: after), "only the language key changes")
        try check(appearance.appearance == .dark && SelfConfigurationStore(defaults: defaults).appearance == .dark,
                  "appearance unchanged by a language change")
        appearance.setAppearanceFromUser(.light)
        try check(language.language == .english && AppLanguageStore(defaults: defaults, preferredLanguages: { preferences }).language == .english,
                  "an appearance change keeps the language")
        let reopened = AppLanguageStore(defaults: defaults, preferredLanguages: { preferences })
        try check(reopened.language == .english && reopened.resolved == .english, "language persists through a fresh store")
        preferences = ["zh-CN"]; reopened.refreshSystemLanguages()
        try check(reopened.resolved == .english, "system refresh cannot override explicit language")
        try check(reopened.setFromUser(.system) && reopened.resolved == .traditionalChinese,
                  "restoring system follows latest language; Simplified Chinese shows Traditional")
        preferences = ["fr-FR"]; reopened.refreshSystemLanguages()
        try check(reopened.resolved == .english, "system language change refreshes resolution; no translation shows English")
        try check(reopened.setFromUser(.english) && appearance.appearance == .light, "language change leaves the appearance")
        defaults.set("unknown-future-language", forKey: AppLanguageStore.preferenceKey)
        let unknown = AppLanguageStore(defaults: defaults, preferredLanguages: { ["en-US"] })
        try check(unknown.language == .system && unknown.resolved == .english, "unknown stored value safely resolves system")
        try check(defaults.string(forKey: AppLanguageStore.preferenceKey) == "unknown-future-language", "loading an unknown value does not rewrite stored data")
        // 简体中文 was a choice until 2026-11-13; a stored one now follows the system.
        defaults.set("zh-Hans", forKey: AppLanguageStore.preferenceKey)
        let retired = AppLanguageStore(defaults: defaults, preferredLanguages: { ["zh-Hans-CN"] })
        try check(retired.language == .system && retired.resolved == .traditionalChinese, "a stored 简体中文 loads as 跟隨系統")
        try check(defaults.string(forKey: AppLanguageStore.preferenceKey) == "zh-Hans", "loading the retired choice does not rewrite it")
        try check(retired.setFromUser(.english) && retired.resolved == .english, "a retired choice can be replaced by Play's choices")
        let resourceChecks = try LanguageResourceChecks.run(resourceRoot: URL(fileURLWithPath: CommandLine.arguments[1]))
        passed += resourceChecks
        print("{\"passed\":\(passed),\"failed\":0,\"actual_userdefaults\":true,\"actual_self_configuration_store\":true,\"native_ios_ui\":false,\"live_model_http_attempts\":0}")
    }
}
