# 渥屋助理 Google Play 版本：初步政策與程式盤點

日期：2026-11-11。基準：`WOOWTECH/woowtech_mika_smart_app` 的 `main`，工作分支 `playstore/woowtech-compliant-20261111`。這是原始碼、合併 Manifest 與公開政策盤點，**不是 Google Play 審核結果**。使用者確認尚未送審，沒有 Play Console 拒件通知；過去 APK 遭 Play Protect 攔截，也不能直接當作商店審核結論。

以下為改造前的基準盤點，並非目前工作樹的建置結果。當時已執行 `:app:processWoowtechReleaseMainManifest`，檢查 `app/build/intermediates/merged_manifest/woowtechRelease/processWoowtechReleaseMainManifest/AndroidManifest.xml`：其中含 `REQUEST_INSTALL_PACKAGES`、`USE_EXACT_ALARM`、`READ_MEDIA_IMAGES`、`WRITE_SECURE_SETTINGS`、`FOREGROUND_SERVICE_SPECIAL_USE`、AccessibilityService 與三個 `specialUse` 服務。`SCHEDULE_EXACT_ALARM` 也出現在當時的合併檔，但 Woowtech 來源 Manifest 將它限於 API 32。下表的「目前程式證據」同樣指改造前版本。

## Play 工作樹進度（2026-11-11）

### 2026-11-12 接續驗證

- `:app:assembleWoowtechDebug` 與聚焦的 `WoowtechManifestTest`、`McpTaskToolsTest` 通過。APK 為 `io.woowtech.assistant` / `0.1.37-play.1`；`brand-check.sh apk` 通過。`aapt2 dump permissions` 只列網路、錄音、網路狀態、前景服務／specialUse、通知、喚醒鎖和 Android 自動產生的內部接收器權限。
- 中繼 Worker 的 `npm run check`、`npm test` 通過；正式 Worker 尚未部署。全套 `:core:test` 執行 3019 項，5 項失敗、3 項跳過。後續已修正其中兩項過時斷言；剩餘 README 生成／翻譯檢查仍未排除。因此不能宣稱全套測試通過。
- POCO 已透過 USB 連線，但 `adb install -r` 回報 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`，商店版未安裝到該機；此輪沒有 POCO 實測通過結果。原本直接下載版的套件未被覆蓋。
- `:app:bundleWoowtechRelease` 成功，產出本機 62 MB AAB（SHA-256 `535cdaec52da2760167d57c51144ec50ef8b1e6d11b38b207b22dfc1e8f6b5f7`）。這只證明可打包，尚未在 Play Console 上傳或審核，也不能以此取代真機驗收。

- `playstore/woowtech-compliant-20261111` 改為 `io.woowtech.assistant`、`targetSdk=36`，與原 APK 套件名稱分開。移除 GitHub APK 更新流程、相片廣泛讀取、精確鬧鐘、無障礙服務、ADB 助手交接與開機恢復入口；附件改用系統 Photo Picker。
- 任務組裝不註冊手機、Root、沙箱、排程及外部 MCP 工具；遠端 MCP 端點不提供讀鎖屏、喚醒或解鎖。電腦連結頁只展示遠端配對；手機設定、復原、Root 及背景計畫入口已隱藏。
- `:app:assembleWoowtechDebug` 成功；APK 的 `aapt2 dump permissions` 未列 `REQUEST_INSTALL_PACKAGES`、`READ_MEDIA_IMAGES`、`USE_EXACT_ALARM`、`SCHEDULE_EXACT_ALARM` 或 `WRITE_SECURE_SETTINGS`。合併 Manifest 未列 AccessibilityService 或 shell 交接 Provider；`brand-check.sh apk` 通過。核心的工具隔離、子代理、Manifest 與文件一致性測試通過；商店版聊天啟動條件亦通過單元測試。這些驗證不等於 Play Console 審核或實機功能驗收。
- **尚未完成**：舊版 Accessibility／ADB／shell 程式碼仍打入 APK，須進一步移除或證明沒有可達路徑；遠端已有手機在線時的唯讀對話與附件 API，但缺少離線儲存、跨裝置寫入與帳號資料同步；AI 回報的 App 流程及中繼收件匣已實作並通過中繼 smoke test，但正式中繼尚未部署。隱私政策／Data safety、三個 `specialUse` 前景服務申報與實機驗收仍待完成。不可把此工作樹標為可送審版本。

後續可達性稽核未找到正常入口能執行跨 App 手機工具：主代理與子代理都沒有註冊手機能力，遠端端點也沒有裝置狀態、喚醒或解鎖。`connectPhone()` 等舊碼仍在 APK 中，屬於未來誤接回能力的維護風險；僅有原始碼存在不能當作已違反無障礙政策的證據。商店版啟動時也已避免建立手機助手狀態監測及遠端解鎖物件。

Android 16 模擬器已對最新 `0.1.37-play.1` APK 執行全新資料安裝、啟動及英／繁中歡迎頁截圖驗證。首次畫面原先仍宣稱能操作 App 並要求手機控制；已修正為對話、語音、瀏覽器、記憶與自備模型帳號／API Key，重新建置與雙語實測通過。模型設定頁能開啟，但模擬器沒有模型帳號或 Key，因此沒有執行真實模型對話、語音辨識、附件或遠端流程。

中繼目前只在手機在線時轉送遠端任務與回覆；本分支已加入手機端經既有權杖驗證的唯讀對話與附件 API，沒有對話或附件的帳號儲存 API。若要手機離線仍可在電腦查閱歷史，須新增伺服器儲存、保留期限與刪除機制。AI 回覆檢舉已加入 App 內送出與本分支中繼接收程式；正式中繼部署及端到端驗證仍待完成。

## 確定需要改的部分

| 項目 | 目前程式證據 | Play 規則與處理方向 |
| --- | --- | --- |
| AI 自主操作其他 App | `.github/README.md` 把背景操作 App 與網頁列為核心；`app/src/main/res/xml/accessibility_service.xml` 要求所有無障礙事件、跨視窗內容、手勢及截圖；`app/src/main/java/com/wangzan101/mika/cap/phone/a11y/AndroidScreen.kt` 與 `core/src/main/kotlin/com/wangzan101/mika/core/agent/AgentLoop.kt` 實作模型驅動的操作迴圈。 | [無障礙政策](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en)明文禁止一般 App 以 Accessibility API 讓代理自主發起、規劃並執行動作／決策。一般語音助理不因可能幫到部分身障者而自動符合無障礙工具例外。商店版需從可執行路徑、UI、服務與聲明中移除這組能力；只藏按鈕或填聲明不足。 |
| App 內 APK 自我更新 | `app/src/main/AndroidManifest.xml` 宣告 `REQUEST_INSTALL_PACKAGES`；`app/src/main/java/com/wangzan101/mika/about/ApkUpdater.kt` 下載 APK；`app/src/main/java/com/wangzan101/mika/ui/UpdateDownloadControls.kt` 引導未知來源安裝並呼叫系統安裝器。 | [安裝套件權限政策](https://support.google.com/googleplay/android-developer/answer/12085295)和[裝置與網路濫用政策](https://support.google.com/googleplay/android-developer/answer/16559646)不容許一般 Play App 用此方式自我更新。商店版刪除權限、下載／安裝入口與更新檔 Provider；改由 Play 更新。 |
| `USE_EXACT_ALARM` | `app/src/woowtech/AndroidManifest.xml` 增加權限；檔內註解已寫明該設定只適用 GitHub APK。 | [精確鬧鐘權限政策](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)主要允許以鬧鐘、計時器或日曆為核心的 App。一般助理提醒不宜宣稱符合。商店版移除 `USE_EXACT_ALARM`，必要時以使用者授權的 `SCHEDULE_EXACT_ALARM` 或不精確排程實作提醒。 |
| 目標 SDK | `app/build.gradle.kts` 設 `compileSdk=36`、`targetSdk=35`。 | [Google Play 2026 目標 API 規則](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)自 2026-08-31 起，手機新 App 與更新需 target API 36。商店版須升至 36 並重新測試背景服務、通知、權限與邊到邊畫面。 |

## 高風險設計，須按商店版範圍處理

| 項目 | 現況與判斷 |
| --- | --- |
| 無線 ADB／shell 輔助程式 | `app/src/main/java/com/wangzan101/mika/cap/phone/setup/`、`cap/phone/shell/` 建立 shell 身分的常駐輔助程式；`app/src/main/AndroidManifest.xml` 宣告 `WRITE_SECURE_SETTINGS`，復原流程可修改無障礙服務設定。這些是手機操控技術鏈的一部分；若商店版不提供跨 App 控制，應一起移除程式入口與權限。是否構成其他政策違規要看實際 APK 行為，不能單憑權限名稱定論。[敏感權限政策](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en)禁止繞過平台安全與隱私控制。 |
| 遠端 MCP／CLI | `app/src/main/java/com/wangzan101/mika/mcp/McpRuntime.kt` 接收遠端任務；`core/src/main/kotlin/com/wangzan101/mika/core/mcp/McpDeviceTools.kt` 可暴露讀鎖屏、喚醒與解鎖工具。商店版如保留同步或對話，需以編譯邊界限制遠端能力，不能只依 UI 開關。遠端解鎖與手機控制是否完全刪除，待產品定位確認。[惡意軟體政策](https://support.google.com/googleplay/android-developer/answer/9888380?hl=en)把未授權遠控列為高風險行為；目前已有權杖與開關，不能直接斷言是惡意軟體。 |
| 相片與檔案 | `app/src/main/AndroidManifest.xml` 宣告 `READ_MEDIA_IMAGES`、`READ_MEDIA_VISUAL_USER_SELECTED`；對話附件也有系統照片選擇器。[相片／影片政策](https://support.google.com/googleplay/android-developer/answer/16935362?hl=en)要求能用系統選擇器時不申請廣泛相片讀取。商店版應移除廣泛相片權限，保留使用者逐次選取附件。 |
| 前景服務 | `app/src/main/AndroidManifest.xml` 的任務、MCP、登入服務使用 `specialUse`，沙箱準備使用 `dataSync`。商店版移除相關功能時同步移除服務；保留者須在 Play Console 逐項申報用途、使用者可見性與示範影片。[前景服務申報](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)。 |
| AI 內容回報 | `app/src/main/java/com/wangzan101/mika/ui/AboutScreen.kt` 有一般 GitHub 問題回報；未在本次搜尋中找到對 AI 回答直接標記不當內容的 App 內流程。[AI 生成內容政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en)要求 App 內可回報冒犯內容；需增設、確認回報送達與處理。 |
| 隱私、帳號、付款 | 模型帳號登入、遠端閘道和敏感資料流需隱私政策與 Data safety 如實揭露；若商店版建立渥屋帳號，需 App 內與網站刪除入口；若銷售 App 內數位功能，須評估 Play Billing。這些依產品實際流程判斷，不能一概稱為已違規。[使用者資料政策](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en)、[付款政策](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en)。 |

## 暫可保留的方向

- 純 App 內 AI 對話、使用者主動錄音轉文字、逐次選擇附件、App 內記憶，以及不操控其他 App 的瀏覽器／資訊查詢，仍需完成內容安全、資料揭露及權限最小化。
- 一般通知與使用者主動開啟的 App 內任務可評估保留；若需要長期背景執行，須重新檢查前景服務類型和必要性。
- GitHub APK 版可繼續在原分支演進；商店版需可重現的獨立建置，避免兩版 UI／Manifest／執行能力互相滲漏。

## 已確認的商店版範圍

1. 保留 AI 對話、語音、瀏覽器與記憶；移除跨 App 自動操作。瀏覽器保留使用者操作的功能；模型可否在 App 內自主操作網頁，需要在能力切分與交易風險檢查後決定具體邊界。
2. 遠端只保留對話與資料同步；不允許遠端操控手機、喚醒或解鎖。
3. 商店版使用**新套件名稱** `io.woowtech.assistant`，與 GitHub APK 版 `io.woowtech.agent` 共存；兩者資料不自動共用。公開搜尋未找到該新 ID，最終可用性仍以 Play Console 建立 App 時為準。
4. **不販售**渥屋自己的訂閱／數位功能，採使用者自備模型帳號或 API Key；現階段不規劃 App 內購買流程。若日後增加數位付費功能，須重新評估 Play Billing。
5. 使用者確認**尚未送 Google Play 審核**，目前沒有可對照的拒件通知。

仍需在資料流程實作時確認商店版是否建立渥屋帳號；若有，補 App 內與網頁刪除入口。

## 下一輪實作與驗證

繼續收斂 Play 建置邊界：完成剩餘手機控制與 shell 路徑的移除或不可達驗證，核對工具清單、UI 導航及測試，再檢查合併 Manifest 和 AAB、在實機跑對話／語音／附件／登入／遠端保留功能，完成 Play Console 權限、Data safety、內容與 FGS 申報。提交審核前不能保證 Google Play 一定核准。
