import Foundation

extension AppLocalizer {
    /// ChatSession still publishes its existing Traditional Chinese status
    /// strings. Translate only the closed settings messages; never treat an
    /// arbitrary server or user string as a localization key.
    func modelSettingsDisplayMessage(_ raw: String) -> String {
        let errors: [(ModelSettingsError, AppText)] = [
            (.invalidURL, .modelSettingsInvalidURL),
            (.missingModel, .modelSettingsMissingModel),
            (.missingKey, .modelSettingsMissingKey),
            (.changedOrigin, .modelSettingsChangedOrigin),
            (.staleSettings, .settingsVisionStale),
            (.invalidKey, .modelSettingsInvalidKey),
            (.unavailableKeychain, .modelSettingsUnavailableKeychain)
        ]
        if let known = errors.first(where: { $0.0.errorDescription == raw }) {
            return text(known.1)
        }
        let keychainPrefix = "Keychain 存取失敗（系統代碼 "
        let keychainSuffix = "），設定未變更。"
        if raw.hasPrefix(keychainPrefix), raw.hasSuffix(keychainSuffix) {
            let code = String(raw.dropFirst(keychainPrefix.count).dropLast(keychainSuffix.count))
            if let status = Int32(code), String(status) == code {
                return text(.modelSettingsKeychainStatus(code: code))
            }
        }
        let notices: [String: AppText] = [
            "設定已儲存，尚未驗證連線。": .settingsModelSaved,
            "新設定已儲存，尚未驗證連線。舊金鑰清理失敗，可用移除功能清除此 App 的模型金鑰。": .settingsModelSavedCleanup,
            "已移除此 App 的模型設定與金鑰；訊息草稿保留。": .settingsModelRemoved,
            "無法讀取或儲存模型設定，請移除設定後重新填寫。": .settingsModelFallbackError
        ]
        return notices[raw].map(text) ?? raw
    }
}
