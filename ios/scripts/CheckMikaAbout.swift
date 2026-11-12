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
            .simplifiedChinese: "关于渥屋助理",
            .english: "About woowtech agent"
        ]
        for language in AppDisplayLanguage.allCases {
            let copy = MikaAboutCopy(language: language)
            try check(copy.text(.title) == expected[language], "About title follows interface language")
            for key in MikaAboutKey.allCases {
                try check(!copy.text(key).isEmpty, "About copy has no empty language entry")
            }
        }
        print("MikaAbout: \(assertions) assertions passed")
    }

    private struct Failure: Error { let message: String }
}
