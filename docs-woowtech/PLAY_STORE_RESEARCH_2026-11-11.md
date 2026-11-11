# 渥屋助理 Google Play 版本：初步政策與程式盤點

日期：2026-11-11。基準：`WOOWTECH/woowtech_mika_smart_app` 的 `main`，工作分支 `playstore/woowtech-compliant-20261111`。這是原始碼與公開政策盤點，**不是 Google Play 審核結果**。尚未提交 AAB、檢查 Play Console 拒件通知，或確認最終合併 Manifest。

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

## 尚待確認的產品決策

1. 商店版是否定位為 AI 對話、語音、瀏覽器與記憶，完全移除跨 App 自動操作；或改成以身障輔助為真正核心的不同產品。
2. 遠端 MCP／電腦連線保留資料同步、限於 App 內任務，還是完全移除。
3. 商店版套件名稱是否與 GitHub 版共存；相同名稱還要處理簽章、升級與資料遷移。
4. 是否販售渥屋自己的訂閱／數位功能；是否建立渥屋帳號。

## 下一輪實作與驗證

決策後建立明確的 Play 建置邊界：先讓 Play 變體完全不包含 AccessibilityService、shell 入口、APK 更新與受限權限，再修 UI 導航、任務能力、測試與文件。最後檢查合併 Manifest 和 AAB、在實機跑對話／語音／附件／登入／遠端保留功能，完成 Play Console 權限、Data safety、內容與 FGS 申報。提交審核前不能保證 Google Play 一定核准。
