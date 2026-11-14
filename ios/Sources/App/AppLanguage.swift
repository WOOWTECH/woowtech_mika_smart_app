import Foundation

/// Interface language only. Never changes prompts, user data or model output.
/// 简体中文 ("zh-Hans") was a choice until 2026-11-13; it is no longer a case, so
/// a stored one loads as .system like any unknown value (see AppLanguageStore).
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case traditionalChinese = "zh-Hant"
    case english = "en"

    /// The choices Settings offers, as in the Play edition (brand.properties
    /// ui.languages=en,zh-Hant).
    static let settingsChoices: [AppLanguage] = [.system, .traditionalChinese, .english]

    func resolve(preferredLanguages: [String]) -> AppDisplayLanguage {
        switch self {
        case .traditionalChinese: return .traditionalChinese
        case .english: return .english
        case .system:
            // The first system language the app has an interface for decides;
            // with none of them, English.
            return preferredLanguages.lazy.compactMap(AppDisplayLanguage.init(systemLanguage:)).first ?? .english
        }
    }
}

/// The interface languages, as in the Play build: English and Traditional Chinese.
enum AppDisplayLanguage: String, CaseIterable {
    case english = "en"
    case traditionalChinese = "zh-Hant"

    /// The interface for one system language, by the owner's rule of 2026-11-13
    /// (簡中用繁中跟其他語言用英文). English shows English. Chinese shows Traditional
    /// Chinese in either script: Traditional (zh-Hant, zh-TW, zh-HK, zh-MO) has a
    /// translation, and Simplified (zh-Hans, zh-CN, zh-SG, a bare zh) uses it too, so
    /// the script never has to be guessed. Cantonese (yue) counts as Chinese, as iOS
    /// gives it the app's zh-Hant resources. Any other language has no translation.
    init?(systemLanguage identifier: String) {
        switch Locale.Language(identifier: identifier).languageCode?.identifier {
        case "en": self = .english
        case "zh", "yue": self = .traditionalChinese
        default: return nil
        }
    }
}
