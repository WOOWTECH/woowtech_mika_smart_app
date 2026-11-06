# 渥屋助理（woowtech agent）fork 說明

上游：[wangzan101/Mika](https://github.com/wangzan101/Mika)（Apache-2.0）。這份文件記錄 WOOWTECH 版跟上游的每一處刻意差異、為什麼這樣改，以及怎麼跟上游同步。改 fork 時，這份文件要一起更新。

## 基準

| 項目 | 值 |
|---|---|
| 切出點 | 上游 `v0.1.37`（`2c4563bc`，2026-11-05） |
| 合併 owner 建的 README commit | `e0108381`（`--allow-unrelated-histories`） |
| applicationId | `io.woowtech.agent`（Kotlin package 維持上游的 `com.wangzan101.mika`） |
| 版本 | `<上游版本>-woow.<N>`；versionCode＝上游 × 100 + N（`app/brand.gradle.kts` 的 `woowtechRevision`） |
| 發佈 | 只發 APK，放本 repo 的 GitHub Releases；不上 Google Play |

## 品牌層怎麼運作

- `app/brand.gradle.kts`：flavor 維度 `brand`。`upstream` 就是上游原樣，上游的單元測試、金樣測試、儀器測試都跑在它上面；`woowtech` 是發行用的版本（`assembleWoowtechRelease`）。
- 品牌值只有一個來源：`app/src/woowtech/resources/brand.properties`，由 `core/.../brand/Brand.kt` 讀取。沒有這個檔時，所有值都退回上游原值。
- 介面字串：Gradle 設定時，把 `src/main/res`（英文、繁中）裡提到 Mika 或上游 repo 的字串，自動換成品牌名和本 repo，產生到 `app/.gradle/woowtech-brand-res`（不進 git）。`app/src/woowtech/res` 裡人工寫的 key 不會被覆蓋。上游新增或修改字串，下次建置會自動跟上。
- 給模型看的內部文字（工具結果、系統說明）維持「Mika」。人設段（`prompts/system/identity.md`）開頭換成品牌名，並補一段說明：內部說的 Mika 就是它自己，對使用者一律自稱渥屋助理。
- 語言：woowtech 版只出英文和繁中（`resourceConfigurations`、`res/xml/locales_config.xml`、`ui.languages` 三處一致）。

## 上游檔案的改動（都標了 `WOOWTECH fork` 註解，或在 `Brand.*` 呼叫處）

| 檔案 | 改什麼 | 原因 |
|---|---|---|
| `app/build.gradle.kts` | 最後一行 `apply(from = "brand.gradle.kts")` | 品牌層入口 |
| `core/.../prompt/Prompts.kt` | `read()` 經過 `Brand.prompt()` | 人設改名 |
| `core/.../chatgpt/ChatGptAuth.kt`、`core/.../oauth/OpenRouterAuth.kt` | 給 OpenAI、OpenRouter 看的 App 名稱 | 第三方同意頁顯示正確產品名 |
| `core/.../mcp/McpRpc.kt`、`core/.../cap/mcp/{McpOAuth,HttpMcpClient,LegacySseMcpClient,StdioMcpClient}.kt`、`app/.../settings/McpServerStore.kt` | MCP 伺服器與用戶端的名稱、說明、登入結果頁 | 電腦端和外部 MCP 伺服器看得到 |
| `core/.../shell/HelperHandoff.kt`、`core/.../mcp/McpUsb.kt` | USB 腳本印給使用者的訊息 | 使用者看得到 |
| `core/.../selfcheck/SelfCheckReport.kt`、`app/.../about/Diagnostics.kt` | 自檢報告、診斷資訊的標題與內文 | 使用者會貼到 issue |
| `core/.../agent/StopRules.kt` | 「模型不支援工具」的提示 | 使用者看得到 |
| `app/.../about/MikaLinks.kt` | repo、Releases、issue、更新 API 改讀 `Brand` | 更新來源與回報管道換成本 repo |
| `app/.../MikaApp.kt`、`app/.../about/UpdateChecker.kt`、`app/.../about/ApkUpdater.kt` | User-Agent、下載通知標題 | 第三方與使用者看得到 |
| `app/.../ui/{ChatCopy,ChatDrawer,AboutScreen}.kt`、`app/.../task/TaskService.kt`、`app/.../capsule/{CapsuleContent,CapsuleCardModel,CapsuleCardContent}.kt` | 寫死的「Mika」改用 `R.string.app_name` | 介面標題、通知、膠囊 |
| `app/.../cap/sandbox/ShareExporter.kt` | 匯出資料夾 `Download/woowtech agent/` | 使用者看得到 |
| `app/.../cap/phone/shell/adb/AndroidAdb.kt` | ADB 金鑰名稱 `woowtech-agent@<機型>` | 顯示在「無線偵錯 › 已配對的裝置」 |
| `app/.../ui/theme/Colors.kt` | accent 改讀品牌色（淺色 `#4069FB`、深色 `#6183FC`） | 品牌色；白字對比 4.53:1 |
| `app/.../browser/AddressInput.kt` | 預設搜尋改 Google | 台灣使用習慣 |
| `app/.../ui/SettingsSubPages.kt` | 語言清單只列品牌支援的語言 | 跟出貨語言一致 |
| `app/.../ui/LicensesScreen.kt` | 第三方清單經 `BrandLicenses` | 列出上游 Mika 署名、補 ML Kit |
| `NOTICE` | 加 WOOWTECH 段落 | Apache-2.0 §4(d) |

新增的檔案：`core/.../brand/Brand.kt`、`core/src/test/.../brand/BrandValuesTest.kt`、`app/brand.gradle.kts`、`app/src/woowtech/**`、`app/src/main/java/.../woowtech/BrandLicenses.kt`、`.github/README.md`（repo 首頁）、`.github/workflows/woowtech.yml`、`docs-woowtech/**`、`woowtech/tools/**`。

## 刻意不改的

- Kotlin package、類別名稱、Keystore alias、SharedPreferences 名稱、虛擬螢幕名稱、OTel 屬性：使用者看不到，改了只會增加同步衝突。
- 沙盒裡的 `mika` 指令、MCP 工具名（`mika_run_task` 等）、relay 協定識別字：屬於介面，改了電腦端工具會壞。
- 根目錄 `README.md`、`docs/`：上游原文，上游測試會檢查它們。WOOWTECH 的說明放 `.github/README.md` 和 `docs-woowtech/`。
- 高風險功能（存 PIN 遠端解鎖、root、xAI 帳號登入、自主模式）：owner 2026-11-06 決定保留。

## 已知缺口（之後處理）

- 電腦端 CLI（`tools/mika`）把套件名寫死為 `com.wangzan101.mika`，USB 連線認不得 `io.woowtech.agent`；區網 MCP 不受影響。
- App 內文件連結指向本 repo 的 `docs/`（上游原文，內容寫的是 Mika）；之後補繁中的設定教學。
- 授權頁的上游說明是寫死的簡體中文。
- 外部 AI 看到的 MCP 工具說明仍寫 Mika（說明段已改成品牌名）。

## 跟上游同步

1. 每週一次：`git fetch upstream --tags`，看這週的上游 tag。
2. 先審 `git diff <上次基準>..<新 tag>`：新權限、新端點、可疑的下載或執行、動到上表檔案的地方。上游大量由 AI 撰寫，網路上也有惡意的山寨 fork，**沒審過不合併**。
3. 開分支 `woowtech/sync-<tag>`，合併上游 tag，解衝突（大多在上表檔案）。
4. 跑 CI：上游測試（upstream flavor）、`BrandValuesTest`、`woowtech/tools/brand-check.sh`、`woowtech/tools/check-no-cn-services.sh`，以及 woowtech release 建置。
5. 在下面的同步紀錄寫一行：基準、拿了什麼、刻意沒拿什麼。

## 同步紀錄

| 日期 | 上游基準 | 說明 |
|---|---|---|
| 2026-11-06 | `v0.1.37` | 初版品牌層 |
