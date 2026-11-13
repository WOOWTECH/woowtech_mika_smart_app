# App Store 發行（本機 Xcode 帳號路徑）

本文件說明在已登入開發者帳號的 Mac 上，自己產生並上傳 App Store 版的步驟。CI 用的簽章 secrets 路徑見 [IOS_DISTRIBUTION.md](IOS_DISTRIBUTION.md)。兩條路徑使用同一份發行檢查（`scripts/release_ios.py`）。

這份文件只寫流程；金鑰、審查用模型設定、帳號資訊都不放在這個公開 repo。

## 前提

- Xcode 26 以上：Apple 自 2026-04-28 起要求上傳的 App 使用 iOS 26 SDK 以上。2026-11-13 在 MacBook 用 Xcode 27.0（27A266a，iOS 27.0 SDK）驗證過。
- 登入鑰匙圈裡有團隊 `W4UWZ8NP2P` 的 Apple Distribution 憑證（含私鑰），Xcode › Settings › Accounts 也登入了該團隊的帳號。
- XcodeGen 2.44.1 在 `PATH` 上。

## 1. 發行檢查（每次都要先跑）

```sh
python3 scripts/release_ios.py build --output build/release-check
```

這是未簽章的 Release 裝置建置，會檢查實際產物：

- 最低系統是 iOS 17.0。
- 九個二進位檔都只有 arm64。
- 不含 ATS 例外。
- 相機、麥克風、照片、語音辨識的用途說明都不是空的。
- 支援 Documents 共享。

隱私清單的檢查方式：腳本讀取每個二進位檔引用的符號和 selector（Apple 上傳時 ITMS-91053 也是這樣檢查），用到需要宣告理由的 API 類別時：

- App 的 `PrivacyInfo.xcprivacy` 必須宣告該類別。
- 如果是框架用到，框架自己的 `PrivacyInfo.xcprivacy` 也要宣告。

框架的清單放在 `Configuration/PrivacyManifests/<框架>/`，由 `project.yml` 加到各框架的資源。新增用到檔案時間、可用空間、開機時間、UserDefaults 或鍵盤清單的程式時，要同時更新對應的清單，否則這一步會失敗。

## 2. 封存

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Release \
  -destination "generic/platform=iOS" -archivePath build/WoowAssistant.xcarchive \
  DEVELOPMENT_TEAM=W4UWZ8NP2P CODE_SIGN_STYLE=Automatic archive
```

封存時用的是開發簽章，匯出時才會改用發行簽章。

## 3. 匯出或上傳

`Configuration/ExportOptions-AppStore.plist` 預設是 `destination=export`，只在本機產生 IPA。

```sh
xcodebuild -exportArchive -archivePath build/WoowAssistant.xcarchive \
  -exportOptionsPlist Configuration/ExportOptions-AppStore.plist -exportPath build/export
```

- 第一次匯出時，帳號裡還沒有 `io.woowtech.assistant` 的 App ID 和 App Store 描述檔，匯出會失敗並顯示「No profiles for 'io.woowtech.assistant' were found」。
- 加上 `-allowProvisioningUpdates`，Xcode 會自動註冊 App ID 並建立描述檔。**這會改動開發者帳號，執行前要先取得 owner 同意。**
- 要直接上傳到 App Store Connect，就把 `destination` 改成 `upload`。上傳前，App Store Connect 要先建立這個 App 的紀錄（名稱、主要語言、Bundle ID、SKU）。上傳同樣要先取得 owner 同意。

## 4. 每次上傳前的人工確認

- 版本號 `MARKETING_VERSION` 和建置號 `CURRENT_PROJECT_VERSION`（在 `project.yml`）要比 App Store Connect 上已有的建置大。
- 送審版本的審查備註要附可用的模型設定。App 沒有帳號，但沒有模型就不能送出訊息。這組設定只填在 App Store Connect，不寫進 repo。
- App 內和 App Store Connect 的隱私權政策網址要一致，而且要能打開。
- 截圖不能出現金鑰、模型網址、個人資料或通知。

## 紀錄

- 2026-11-13（MacBook，Xcode 27.0）：
  - `3ac33840` 加上 required-reason 修正後，`release_ios.py build` 通過，報告記錄四個類別：DiskSpace、FileTimestamp、SystemBootTime、UserDefaults。
  - Release 封存成功（開發簽章）。
  - App Store 匯出停在缺少描述檔，沒有使用 `-allowProvisioningUpdates`，沒有改動帳號，也沒有上傳。
