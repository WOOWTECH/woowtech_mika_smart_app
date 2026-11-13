import Foundation

/// Interface language only. Never changes prompts, user data or model output.
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    /// The choices Settings offers, as in the Play edition (brand.properties
    /// ui.languages=en,zh-Hant). 简体中文 is no longer offered.
    static let settingsChoices: [AppLanguage] = [.system, .traditionalChinese, .english]

    func resolve(preferredLanguages: [String]) -> AppDisplayLanguage {
        switch self {
        case .traditionalChinese: return .traditionalChinese
        case .simplifiedChinese: return .simplifiedChinese
        case .english: return .english
        case .system:
            let compatible = preferredLanguages.filter {
                let code = Locale(identifier: $0).language.languageCode?.identifier
                return code == "en" || code == "zh"
            }
            guard !compatible.isEmpty else { return .traditionalChinese }
            let supported = AppDisplayLanguage.allCases.map(\.rawValue)
            let selected = Bundle.preferredLocalizations(from: supported, forPreferences: compatible).first
            return selected.flatMap(AppDisplayLanguage.init(rawValue:)) ?? .traditionalChinese
        }
    }
}

enum AppDisplayLanguage: String, CaseIterable {
    // Preserve the existing Traditional Chinese interface when none match.
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
}
