import XCTest
@testable import WoowAssistant

@MainActor final class MikaSettingsLocalizationTests: XCTestCase {
    func testPackagedSettingsCopyAndExistingStatusMessagesUseChosenLanguage() throws {
        let samples: [(AppDisplayLanguage, String, String, String, String)] = [
            (.traditionalChinese, "設定", "常用", "主模型", "尚未儲存金鑰。"),
            (.simplifiedChinese, "设置", "常用", "主模型", "尚未保存密钥。"),
            (.english, "Settings", "Common", "Main model", "No key saved.")
        ]
        for (language, title, group, role, missingKey) in samples {
            let localizer = AppLocalizer(language: language)
            for (key, expected) in [(AppText.settingsHomeTitle, title),
                                    (.settingsHomeBasic, group),
                                    (.settingsModelMain, role),
                                    (.settingsModelKeyMissing, missingKey)] {
                let resolved = localizer.resolve(key)
                XCTAssertEqual(resolved.text, expected)
                XCTAssertEqual(resolved.language, language)
                XCTAssertFalse(resolved.usedFallback)
            }
            for (raw, expected) in [
                ("設定已儲存，尚未驗證連線。", AppText.settingsModelSaved),
                ("新設定已儲存，尚未驗證連線。舊金鑰清理失敗，可用移除功能清除此 App 的模型金鑰。", .settingsModelSavedCleanup),
                ("已移除此 App 的模型設定與金鑰；訊息草稿保留。", .settingsModelRemoved)
            ] {
                XCTAssertEqual(localizer.modelSettingsDisplayMessage(raw), localizer.text(expected))
            }
            for error in [ModelSettingsError.invalidURL, .missingModel, .missingKey,
                          .changedOrigin, .invalidKey, .unavailableKeychain] {
                let raw = try XCTUnwrap(error.errorDescription)
                XCTAssertEqual(localizer.modelSettingsDisplayMessage(raw),
                               localizer.text(AppLocalizer.modelSettingsError(error)))
            }
            XCTAssertEqual(localizer.modelSettingsDisplayMessage("Keychain 存取失敗（系統代碼 -25300），設定未變更。"),
                           localizer.text(.modelSettingsKeychainStatus(code: "-25300")))
            XCTAssertEqual(localizer.modelSettingsDisplayMessage("來自服務的原始訊息"), "來自服務的原始訊息")
        }
    }
}
