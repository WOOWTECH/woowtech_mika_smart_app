# 渥屋助理商店版：送審進度與交接

更新：2026-11-13，Asia/Taipei。套件 `io.woowtech.assistant`，候選版 `0.1.37-play.3`、`versionCode=3`、target API 36。**目前尚未經 Play Console 上傳或送審；是否已存在同套件草稿仍待 Console 確認。** 本檔只記已完成的實測及仍需執行的事項，不把模擬器安裝當作 Play 安裝。

## 已完成

| 項目 | 證據與界線 |
| --- | --- |
| AI 回覆檢舉 | 正式 `assistant-relay.woowtech.io` 收件、管理員讀取、錯誤金鑰拒絕、App 內自行刪除及二次刪除 404 已實測；測試資料已清除。30 天到期和定期清理有固定時間與分頁測試，尚不能以當天測試代替實際 30 天營運觀察。操作見 `PLAY_AI_REPORT_OPERATIONS.md`。 |
| 內容防護 | 商店變體只顯示 OpenAI、Anthropic、Gemini 官方 API 和 ChatGPT 帳號登入；儲存、模型列表、試呼叫、正式模型執行與語音轉寫也檢查官方端點。舊自訂端點設定保留供辨識與移除，但不執行。主工作與子任務加上 Play 版安全規則。單元測試涵蓋偽造主機、非標準埠、帳密與 query、模型列表轉址、既有不支援設定。**供應商安全措施與提示詞不能保證完全避免違規內容**，仍須由負責人檢視檢舉、修正並回歸測試。[Google AI 內容政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en) |
| 隱私與資料申報底稿 | 公開雙語頁 `https://assistant-relay.woowtech.io/privacy/play` 已更新並回讀 200；揭露對話、附件、語音、MCP、使用者主動傳送的診斷紀錄與檢舉資料。Data safety 逐題工作表在 `PLAY_DATA_SAFETY_WORKSHEET_2026-11-12.md`，尚未填 Console。 |
| 套件精簡與加密 | 商店 AAB 不含沙箱 rootfs、PRoot、mikarun、ML Kit OCR 依賴與其 native 檔；Apporo／上游變體保留。商店版模型只走官方 HTTPS，遠端 MCP 和診斷網址須 HTTPS。 |
| 實機和模擬器 | 已把當前原始碼重新建置的 `play.3` Debug APK 以 ADB 更新至 POCO：真實 ChatGPT 短對話成功，HA MCP 列出 77 工具，記憶／技能頁與公開隱私頁可開啟，舊自訂供應商標示不支援；橫向側欄能捲到最近對話及設定。測試對話已刪除，原 GitHub 版已回前景。另從簽章 AAB 派生分割 APK 安裝於全新 Android 36 模擬器，核對中英文模型設定只出現官方供應商。詳細界線見 `PLAY_POCO_ACCEPTANCE_2026-11-12.md`；均不等於 Play 商店安裝。 |
| 乾淨安裝補驗 | 2026-11-13 將簽章 AAB 透過 bundletool 派生 APK，以 Debug 憑證安裝至已清除資料的 Android 36 Google APIs 模擬器；英／繁中歡迎頁及模型設定正常，只見 ChatGPT 和 OpenAI、Anthropic、Gemini 官方選項，無 Key 時儲存與下一步不可按。ChatGPT 登入會啟動前景服務並開啟瀏覽器，回 App 取消後服務停止；沒有完成帳號登入或模型對話。這臺模擬器沒有 Play Store，不能當作 Play 軌道安裝。 |
| 商店素材 | icon、feature graphic、雙語歡迎與模型設定截圖已準備；四張英／繁中截圖已從這次 AAB 衍生安裝重拍並確認 RGB 像素與原始擷取一致。公開隱私頁、支援網站與兩支前景服務影片 URL 在 2026-11-13 回 200。影片展示使用者如何觸發功能；最終仍以 Console 審查為準。對話、瀏覽器、記憶的商店截圖要在 Play 安裝後補拍，現在不得把早期 Debug 實測說成 Play 截圖。 |
| 簽章候選包 | 專用上傳金鑰已用於 `bundleWoowtechRelease`；bundletool 驗證成功、`jarsigner` 回報 `jar verified`。`tools/build-play-candidate.sh` 要求私有簽章設定與 bundletool，並攔截未簽章包、套件名稱錯誤、缺少 16 KB 對齊及誤包入直接下載版執行環境。每次程式碼提交後都須重建包並記錄 SHA-256；Google Play App Signing 與從 Play 商店安裝另需驗收。 |

## 仍需完成才能提交

1. **審查員模型憑證。** 使用者已選擇準備一把可持續用於審查、限制用量的專用 OpenAI、Anthropic 或 Gemini 官方 API Key 和模型名。先在乾淨的 Play 安裝驗證對話，再把憑證填進 Play Console 限制存取欄位；不放在 Git、聊天或公開商店文案。舊的自訂 Base URL 不能用於本版審查。[App access](https://support.google.com/googleplay/android-developer/answer/15748846?hl=en)
2. **Play Console 表單與上傳。** Chrome 已登入 WOOWTECH 機構帳戶，但本次 `System Events` 自動化再次 AppleEvent 逾時 `-1712`，所以尚未能確認草稿、建立 App 或上傳 AAB。取得可操作的 Console 後填商店圖文、分級、目標對象、廣告、Data safety、AI 內容、App access、隱私政策與前景服務聲明。草稿見 `PLAY_CONSOLE_REVIEW_INPUT_DRAFT.md`。
   - 這個套件名稱曾以 Debug 簽章安裝在 POCO。Google 的 Android 開發者驗證說明指出，若新 Play App 的套件名稱先在已認證裝置使用，Console 可能要求驗證當時的簽章私鑰所有權；遇到該提示時依 Console 流程使用本機既有的 Debug 簽章材料，不應猜測已自動通過。[官方說明](https://developer.android.com/developer-verification/assets/pdfs/updates-to-play-console-for-android-developer-verification.pdf)
3. **前景服務申報。** Manifest 有 `TaskService` 及 `ChatGptSignInService` 兩項 `specialUse`，各需用途、啟動／停止與中斷影響說明，並提交已準備的示範影片。公開說明要求影片展示 App 中觸發功能的步驟；兩片均已涵蓋。Console 仍須實際接受用途與影片。[FGS 申報](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)
4. **Play 內測。** 使用和提交版本一致的簽章 AAB，核對 manifest／16 KB 相容性後上傳內部測試。先從 Play 安裝至乾淨的測試裝置或可使用 Play 的模擬器，依 `PLAY_INTERNAL_TEST_CHECKLIST_2026-11-13.md` 驗證首次設定、官方模型對話、HTTPS MCP、語音、瀏覽器、技能／記憶、檢舉與刪除；內測通過後才進入正式送審流程。現有 Android 36 Google APIs 模擬器沒有 Play Store。POCO 現有同套件 Debug 憑證已確認不同於本機上傳憑證；Play 分發憑證仍須在 Console 核對，若不同便不能直接覆蓋。須先決定 POCO 的資料保留／遷移方案，**不得為了內測直接解除安裝並清掉既有資料**。[Android 更新簽章規則](https://developer.android.com/google/play/app-updates)、[Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en)
5. **營運交接。** 指派實際每日處理檢舉的人員，確認隱私聯絡信箱持續可收件；依 `PLAY_AI_REPORT_OPERATIONS.md` 留下去識別化的處理紀錄。

較早研究 `PLAY_REVIEW_READINESS_2026-11-12.md` 為歷史紀錄，其中 `play.2`、未簽章包與未公開隱私政策的狀態已被本檔更新。
