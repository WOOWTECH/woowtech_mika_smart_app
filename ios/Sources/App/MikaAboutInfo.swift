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

/// About-only copy stays separate from the generated shared AppText catalog.
enum MikaAboutKey: CaseIterable {
    case title, group, version, build, unavailable, installedVersion, tagline
    case resources, repository, guide, feedback, license
    case diagnostics, diagnosticsNote, diagnosticsCopy, diagnosticsCopied, diagnosticsShare, close

    var translations: (hant: String, hans: String, en: String) {
        switch self {
        case .title: return ("關於渥屋助理", "关于渥屋助理", "About woowtech agent")
        case .group: return ("其他", "其他", "Other")
        case .version: return ("版本", "版本", "Version")
        case .build: return ("建置", "构建", "Build")
        case .unavailable: return ("版本資訊不可用", "版本信息不可用", "Version unavailable")
        case .installedVersion: return ("此裝置目前安裝的 App 版本", "此设备当前安装的 App 版本", "App version installed on this device")
        // Android About's product description, adapted for both iPhone and iPad.
        case .tagline: return ("你的私人助理，替你把事辦成", "你的私人助理，替你把事办成", "Your personal assistant, getting things done for you")
        case .resources: return ("資源與支援", "资源与支持", "Resources and support")
        case .repository: return ("開源專案", "开源项目", "Source repository")
        case .guide: return ("專案說明", "项目说明", "Project guide")
        case .feedback: return ("回報問題", "反馈问题", "Report an issue")
        case .license: return ("開源授權", "开源许可", "Open-source license")
        case .diagnostics: return ("診斷資訊", "诊断信息", "Diagnostic information")
        case .diagnosticsNote: return ("請先檢視資訊，再自行複製或分享。", "请先查看信息，再自行复制或分享。", "Review this information before copying or sharing it.")
        case .diagnosticsCopy: return ("複製", "复制", "Copy")
        case .diagnosticsCopied: return ("已複製", "已复制", "Copied")
        case .diagnosticsShare: return ("分享", "分享", "Share")
        case .close: return ("完成", "完成", "Done")
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
        return ["woowtech assistant diagnostics", "App version: \(info.version ?? copy.text(.unavailable))",
                "Build: \(info.build ?? copy.text(.unavailable))", "iOS/iPadOS: \(os)"].joined(separator: "\n")
    }
}

enum MikaAboutLinks {
    static let repository = URL(string: "https://github.com/WOOWTECH/woowtech_mika_smart_app")!
    static let guide = URL(string: "https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/main/README.md")!
    static let feedback = URL(string: "https://github.com/WOOWTECH/woowtech_mika_smart_app/issues")!
    static let license = URL(string: "https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/main/LICENSE")!
}

struct MikaAboutCopy {
    let language: AppDisplayLanguage

    func text(_ key: MikaAboutKey) -> String {
        let choices = key.translations
        switch language {
        case .traditionalChinese: return choices.hant
        case .simplifiedChinese: return choices.hans
        case .english: return choices.en
        }
    }
}
