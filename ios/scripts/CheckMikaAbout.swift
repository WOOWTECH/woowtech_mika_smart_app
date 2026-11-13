import Foundation

@main enum CheckMikaAbout {
    static func main() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(message: message) }
            assertions += 1
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("woow-about-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ extra: [String: Any]) throws -> Bundle {
            let url = root.appendingPathComponent(UUID().uuidString + ".bundle", isDirectory: true)
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var plist: [String: Any] = ["CFBundleIdentifier": "io.woowtech.about.fixture",
                                        "CFBundlePackageType": "BNDL"]
            plist.merge(extra) { _, new in new }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            guard let bundle = Bundle(url: url) else { throw Failure(message: "Fixture bundle not loaded") }
            return bundle
        }

        let installed = MikaAboutInfo(bundle: try fixture([
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "42"
        ]))
        try check(installed.version == "0.1.0", "Read the installed short version")
        try check(installed.build == "42", "Read the installed build number")

        let absent = MikaAboutInfo(bundle: try fixture([:]))
        try check(absent.version == nil && absent.build == nil, "Missing metadata stays unavailable")

        let unresolved = MikaAboutInfo(bundle: try fixture([
            "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "line\nbreak"
        ]))
        try check(unresolved.version == nil && unresolved.build == nil,
                  "Do not display build placeholders or control characters")

        let report = MikaAboutDiagnostics(info: installed,
            osVersion: OperatingSystemVersion(majorVersion: 17, minorVersion: 2, patchVersion: 1),
            language: .english).text
        try check(report == "woowtech assistant diagnostics\nApp version: 0.1.0\nBuild: 42\niOS/iPadOS: 17.2.1",
                  "Report contains only the explicitly selected metadata")
        let missingReport = MikaAboutDiagnostics(info: unresolved,
            osVersion: OperatingSystemVersion(majorVersion: 17, minorVersion: 0, patchVersion: 0),
            language: .english).text
        try check(!missingReport.contains("$(") && !missingReport.contains("line\nbreak"),
                  "Report does not include invalid bundle values")

        let expected = [
            AppDisplayLanguage.traditionalChinese: "關於渥屋助理",
            .english: "About woowtech agent"
        ]
        // woowtech Play edition about_tagline, about_version and about_build.
        let taglines: [AppDisplayLanguage: String] = [
            .traditionalChinese: "在同一個地方對話、瀏覽網頁，並記住有用的資訊",
            .english: "Chat, browse, and keep useful information in one place"
        ]
        let versionLines: [AppDisplayLanguage: (String, String)] = [
            .traditionalChinese: ("版本 0.1.0", "建置 42"),
            .english: ("Version 0.1.0", "Build 42")
        ]
        for language in AppDisplayLanguage.allCases {
            let copy = MikaAboutCopy(language: language)
            try check(copy.text(.title) == expected[language], "About title follows interface language")
            try check(copy.text(.tagline) == taglines[language], "About tagline follows interface language")
            try check(copy.version("0.1.0") == versionLines[language]?.0, "Version line follows Android about_version")
            try check(copy.build("42") == versionLines[language]?.1, "Build line follows Android about_build")
            try check(copy.text(.feedbackSheetDetail).contains("woowtech@designsmart.com.tw"), "Feedback names the support address")
            for key in MikaAboutKey.allCases {
                try check(!copy.text(key).isEmpty, "About copy has no empty language entry")
            }
        }
        // No Simplified Chinese column (2026-11-13): a Simplified Chinese system reads the Traditional one.
        let simplifiedSystem = MikaAboutCopy(language: AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"]))
        try check(simplifiedSystem.text(.title) == "關於渥屋助理" && simplifiedSystem.build("42") == "建置 42",
                  "A Simplified Chinese system shows the Traditional Chinese About page")
        let policy = URLComponents(url: MikaPrivacyPolicy.url, resolvingAgainstBaseURL: false)
        try check(policy?.scheme == "https" && policy?.host == "assistant-relay.woowtech.io" && policy?.path == "/privacy/ios"
                  && policy?.query == nil && policy?.fragment == nil, "The privacy policy is one HTTPS address")
        try check(MikaAboutCopy(language: .traditionalChinese).text(.privacyPolicy) == "隱私權政策"
                  && MikaAboutCopy(language: .english).text(.privacyPolicy) == "Privacy policy", "Privacy policy row in both languages")
        print("MikaAbout: \(assertions) assertions passed")
    }

    private struct Failure: Error { let message: String }
}
