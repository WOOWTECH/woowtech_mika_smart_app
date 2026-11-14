import Foundation

/// Read the installed app's metadata. An absent or unresolved build setting is
/// shown as unavailable instead of presenting a guessed version number.
struct MikaAboutInfo: Equatable {
    let version: String?
    let build: String?

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        version = Self.displayValue(info["CFBundleShortVersionString"])
        build = Self.displayValue(info["CFBundleVersion"])
    }

    private static func displayValue(_ raw: Any?) -> String? {
        guard let string = raw as? String else { return nil }
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 64,
              !value.contains("$("), !value.contains("${"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return value
    }
}

/// The privacy policy that the AI-sharing consent and About › 隱私權政策 open.
/// One constant, so the address can change; the page goes live once the owner
/// has approved its text.
enum MikaPrivacyPolicy {
    static let url = URL(string: "https://assistant-relay.woowtech.io/privacy/ios")!
}

/// About-only copy stays separate from the generated shared AppText catalog.
/// Wording follows the woowtech Play edition's AboutScreen at 465a17c9.
enum MikaAboutKey: CaseIterable {
    case title, group, version, build, unavailable, installedVersion, tagline
    case feedback, feedbackDetail, feedbackSheetDetail, diagnosticsCopyTitle, diagnosticsCopyDetail
    case diagnostics, diagnosticsNote, diagnosticsCopy, diagnosticsCopied, diagnosticsShare, close
    case dataNote, copyright, privacyPolicy, privacyPolicyDetail
    case releasedUnder, licenseLink, licenseTitle, thirdParty, upstreamNote, licenseUnavailable, licensesFooter

    var translations: (hant: String, en: String) {
        switch self {
        case .title: return ("關於渥屋助理", "About woowtech agent")
        case .group: return ("其他", "Other")
        case .version: return ("版本", "Version")
        case .build: return ("建置", "Build")
        case .unavailable: return ("版本資訊不可用", "Version unavailable")
        case .installedVersion: return ("此裝置目前安裝的 App 版本", "App version installed on this device")
        case .tagline: return ("在同一個地方對話、瀏覽網頁，並記住有用的資訊",
                               "Chat, browse, and keep useful information in one place")
        case .feedback: return ("回報問題", "Send feedback")
        case .feedbackDetail: return ("複製診斷資訊 · woowtech@designsmart.com.tw",
                                      "Copy diagnostics · woowtech@designsmart.com.tw")
        case .feedbackSheetDetail: return ("複製診斷資訊後，寄到 woowtech@designsmart.com.tw",
                                           "Copy diagnostics, then email them to woowtech@designsmart.com.tw.")
        case .diagnosticsCopyTitle: return ("複製診斷資訊", "Copy diagnostics")
        // Play lists 版本、機型和設定狀態; the iOS report has version details only.
        case .diagnosticsCopyDetail: return ("版本資訊，寄信時附上", "Version details, to include in your email")
        case .diagnostics: return ("診斷資訊", "Diagnostics")
        case .diagnosticsNote: return ("不包含 API Key、聊天內容和螢幕內容",
                                       "Contains no API keys, chat content or screen content")
        case .diagnosticsCopy: return ("複製", "Copy")
        case .diagnosticsCopied: return ("已複製", "Copied")
        case .diagnosticsShare: return ("分享", "Share")
        case .close: return ("完成", "Done")
        // Play's about_data_note without its sentence on reporting AI replies,
        // which iOS cannot do yet.
        case .dataNote: return ("你送出的內容由你選擇的 AI 服務商處理。",
                                "What you send is processed by the AI provider you choose.")
        case .copyright: return ("© 2026 WOOW TECH CO., LTD. · 基於 wangzan101/Mika（Apache-2.0）",
                                 "© 2026 WOOW TECH CO., LTD. · Based on wangzan101/Mika (Apache-2.0)")
        // iOS: App Review asks for the policy inside the app as well.
        case .privacyPolicy: return ("隱私權政策", "Privacy policy")
        case .privacyPolicyDetail: return ("渥屋助理怎麼處理你的資料", "How woowtech agent handles your data")
        // Play's about_released_under, about_license_link, about_license_title and
        // licenses_third_party; iOS lists its one upstream component and shows its texts.
        case .releasedUnder: return ("基於 %@ 釋出", "Released under %@")
        case .licenseLink: return ("Apache-2.0 開源許可", "Apache-2.0 license")
        case .licenseTitle: return ("Apache-2.0 授權條款", "Apache-2.0 License")
        case .thirdParty: return ("第三方元件 · %lld 個", "Third-party components · %lld")
        case .upstreamNote: return ("記憶、個人技能與操作路線的行為依這個版本改寫成 iOS 版，內建技能的原文也來自這裡。",
                                    "The memory, personal skill and route behavior is adapted for iOS from this revision, which is also the source of the built-in skills' original text.")
        case .licenseUnavailable: return ("授權條款文字目前無法讀取。上游 wangzan101/Mika 以 Apache-2.0 授權釋出。",
                                          "The license text can't be read right now. Upstream wangzan101/Mika is released under the Apache-2.0 license.")
        case .licensesFooter: return ("上面的授權條款全文與版權宣告，取自上游 wangzan101/Mika 的固定版本。",
                                      "The license text and notice above come from the pinned revision of upstream wangzan101/Mika.")
        }
    }
}

/// An allowlisted snapshot; never reads account, network or conversation data.
struct MikaAboutDiagnostics {
    let info: MikaAboutInfo
    let osVersion: OperatingSystemVersion
    let language: AppDisplayLanguage

    var text: String {
        let copy = MikaAboutCopy(language: language)
        let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return ["woowtech agent diagnostics", "App version: \(info.version ?? copy.text(.unavailable))",
                "Build: \(info.build ?? copy.text(.unavailable))", "iOS/iPadOS: \(os)"].joined(separator: "\n")
    }
}

struct MikaAboutCopy {
    let language: AppDisplayLanguage

    func text(_ key: MikaAboutKey) -> String {
        let choices = key.translations
        switch language {
        case .traditionalChinese: return choices.hant
        case .english: return choices.en
        }
    }

    /// Android about_version and about_build: 版本 %1$s, 建置 %1$s.
    func version(_ value: String) -> String { text(.version) + " " + value }
    func build(_ value: String) -> String { text(.build) + " " + value }
    /// Android about_released_under around about_license_link.
    var releasedUnderParts: (before: String, after: String) {
        let parts = text(.releasedUnder).components(separatedBy: "%@")
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }
    func thirdParty(_ count: Int) -> String {
        text(.thirdParty).replacingOccurrences(of: "%lld", with: String(count))
    }
}
