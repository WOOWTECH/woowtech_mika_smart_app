# 渥屋助理 Google Play 上架研究與送審準備

檢查時間：2026-11-12，Asia/Taipei。這是上架準備記錄，**不是 Google 的審核結果**。本次未上傳 AAB、未送審、未發布服務，也未在 Play Console 修改設定。

## 已核對的版本與證據

- 商店分支 `playstore/woowtech-compliant-20261111`，檢查時 HEAD 為 `2ac89a89`。原始碼設定套件 `io.woowtech.assistant`、`versionCode=2`、`0.1.37-play.2`、target API 36。Google 要求一般手機新 App 與更新自 2026-08-31 起 target API 36 以上；原始碼和本機候選 AAB 的數值符合該條件。[Google 目標 API 規則](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)
- 本機候選 AAB：`app/build/outputs/bundle/woowtechRelease/app-woowtech-release.aab`，64,927,365 bytes，SHA-256 `5f3d9f3c7d35e08280413b130809ae7f44d7f0e3eb7e4596147163c3adfee994`。直接檢查 ZIP 未見 AAB/JAR `.SF`／`.RSA`／`.DSA`／`.EC` 簽章項目；**此候選檔尚無標準上傳簽章**。檔案時間早於上述 commit，不能據時間判定內容是否與該 commit 一致。需從確定的最終 commit 重建、驗證內容並用受控的上傳金鑰簽章；版本碼是否可用取決於 Console 已使用的版本。
- 候選 AAB manifest 經獨立解析為 min API 30、target API 36；含網路、錄音、通知、wake lock 與前景服務權限；未列無障礙服務、`McpService` 或 `SandboxService`。`TaskService` 與 `ChatGptSignInService` 為 `specialUse`。應在最終簽章 AAB 重新檢查；manifest 不足以單獨證明所有程式路徑均不可達。
- POCO `play.2` 已經 ADB 安裝與啟動，但完整真實模型與 MCP 驗收多為 `play.1` 的紀錄；尚無從 Play 測試軌安裝本版的證據。詳見 `PLAY_POCO_ACCEPTANCE_2026-11-12.md`。
- 使用者選取帳戶後，Play Console 首頁明確顯示 WOOWTECH 為**機構帳戶**，首頁列出七個正式版和一個內部測試 App，當中未見 `io.woowtech.assistant`；首頁未列出不等於已排除所有可能的草稿或其他帳戶。此帳戶不屬新個人帳戶的 12 人、14 天規則。尚未確認渥屋助理套件是否能建立、簽章、測試軌與審查狀態。
- 已只讀核對同帳戶三個案例：`io.woowtech.smart`（渥屋智能）、`io.woowtech.odoo`（woowtech platform）、`com.woowtech.aiot`（渥屋科技）皆顯示已有正式版。渥屋智能的「測試及發布」也顯示已有內部測試版，可參考先測試再發布的流程；這些案例不能直接複製其隱私、權限或內容申報。
- 查核三個 Google Play 公開頁列出的既有網站連結：渥屋智能的[隱私政策](https://aiot.woowtech.io/blog/help-center-7/woowtech-smart-app-yin-si-quan-zheng-ce-privacy-policy-391)、platform 的[隱私政策](https://aiot.woowtech.io/odoo-privacy)與[帳號刪除頁](https://aiot.woowtech.io/odoo-account-deletion)、渥屋科技的[隱私政策](https://aiot.woowtech.io/privacy)，本地不帶登入的 HTTP 檢查均回 200 HTML。這可作為助理政策頁的託管參考，不能證明全球可訪問或作為助理自身的資料處理聲明。
- 已查看「建立應用程式」表單，建議填寫名稱 `渥屋助理`、套件 `io.woowtech.assistant`、繁體中文 `zh-TW`、應用程式、免費；名稱與套件仍以建立頁校驗為準。表單要求確認符合所有開發者政策並聲明符合美國出口法律；目前政策工作仍有未完成項目，尚未代表公司勾選、送出或建立草稿。
- 使用本機 Node 22 串行執行 relay worker 的 `npm test` 與 `npm run test:accounts`，兩者均通過。前者包含測試收件、管理讀取與刪除，後者涵蓋兩帳號隔離及配對；測試使用本機 worker 與臨時資料，不代表正式服務已部署或能收件。
- 只讀執行 `wrangler whoami` 時，CLI 已登入，但列出的 Cloudflare 帳戶未包含 worker 設定的目標帳戶。這不證明其他登入方式不可用；部署前需核對目標帳戶存取權及目前線上版本，不應改寫帳戶設定來猜測。

## 舊文件須先釐清

`PLAY_DISCLOSURES_DRAFT.md` 與 `PLAY_PRIVACY_POLICY_DRAFT.md` 仍描述手機遠端配對、中繼讀取對話、Odoo 帳號和已移除的服務；`PLAY_SUBMISSION_HANDOFF_2026-11-12.md` 亦有較舊版狀態。使用者已指定商店版保留**向外連接 MCP 伺服器**，不保留手機對電腦的 MCP 服務及遠端配對。必須先依最終 AAB 和實際流程重盤，不能直接提交舊草稿。

新的 `PLAY_PRIVACY_POLICY_MCP_DRAFT.md` 已按目前產品範圍重寫，仍含待確認項目，不能直接發布。`PLAY_CONSOLE_REVIEW_INPUT_DRAFT.md` 提供建立 App、審查員存取和前景服務素材草稿。

AI 回覆檢舉可能仍傳送到 WoowTech 的 relay 收件端；這與移除手機遠端配對是不同資料流。檢查時不可把前者誤刪，也不能假定它已部署成功。

## 主要待辦與送審證據

| 項目 | 已知狀態 | 下一步 |
| --- | --- | --- |
| AI 檢舉與內容政策 | App 內檢舉表單可開啟，未有正式服務的完整送達驗收。2026-11-12 對設定網址以 App 格式提交一筆不含個資的有效測試 POST，回 `503 device_offline`，未得到受理回應；這次沒有產生已確認的報告。僅憑此回應不能判定根因或代表 App 端完整實測。程式的重試依對話畫面執行，三次後恢復流程待補證據；伺服器程式會拒收建立超過七天的報告。 | 確認並部署正式收件功能後，用專屬測試資料驗證提交、收件、錯誤、恢復及刪除；建立報告審查與處置機制。另驗證支援的自備模型對禁止內容的防護，不能只因使用者自備 Key 就推定政策不適用。Google 要求 AI 生成 App 內可向開發者檢舉內容。[AI 政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en) |
| 隱私政策與資料安全 | 政策草稿有營運資料待決、舊配對敘述，且未完整涵蓋外部 MCP；目前未找到明確 App 內政策入口，亦未證實公開政策已發布。 | 以最終產品的模型、語音、使用者選取檔案、外部 MCP、檢舉及 SDK 實際資料流重寫；確認接收者、用途、保留與刪除，公開可免登入讀取的政策頁，並在 App 與 Play Console 加入口。Google 也要求第三方 SDK 資料處理納入 Data safety。[政策要求](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en)、[Data safety](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) |
| 傳輸加密 | 外部 MCP 對本機／私人網路 HTTP 有使用者可啟用的選項，POCO 先前曾測過本機 HTTP。 | 盤點最終版各種資料、目的端與使用情境，依 Google 對收集、分享與例外的定義作答；不能只看到 HTTPS 的檢舉端點就填寫所有資料均加密。 |
| 審查員存取 | 使用者需自備模型登入或 API Key；現有測試服務曾限流，沒有可證實可供審查的穩定模型。 | 準備在審查期間可用的受限測試服務、必要登入與逐步操作方式，透過 Console App access 提交；不將憑證寫入倉庫。此方案能否被審核使用仍需實際驗證。[準備審查](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en) |
| 前景服務 | 候選 AAB 有 `TaskService` 與 `ChatGptSignInService` 的 `specialUse`。 | 確認兩者實際使用符合政策，準備功能、不可延後或中斷的影響與各自示範影片；特別評估登入流程是否確有必要使用前景服務。[FGS 申報](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en) |
| 帳號刪除 | 舊草稿提到 Odoo／relay 帳號，但該配對功能依產品決策已從商店版移除；目前無法僅憑舊草稿判斷最終版是否讓使用者建立 App 帳號。 | 驗證最終版是否在 App 內或引導外部建立渥屋 App 帳號；若有，須提供 App 內及外部刪除請求途徑與資料處置。模型供應商帳號需按實際流程判斷。[Google 帳號刪除規則](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) |
| 商店圖文 | 已有中英文文案草稿，但尚未確定最終功能、素材與政策 URL。 | 用最終版畫面準備名稱、簡介、完整說明、圖示、宣傳圖與截圖；若採用 AI 生成或編輯素材，按 Console 和現行規則檢查是否需標示。|

## 截圖的實際尺寸問題

本次 POCO `wm size` 顯示 720×1600，長邊約為短邊 2.22 倍。Google 的商店截圖要求長邊不超過短邊兩倍，因此此尺寸的原始截圖不能直接按現行規則提交；可使用符合比例的模擬器或在不誤導使用者的前提下製作符合規格的版面，再驗證實際畫面與最終版一致。Google 要求至少兩張截圖；部分展示推薦另建議至少四張高解析度截圖。[Play 圖片規格](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)

## Console 建議處理順序

1. 已確認 WOOWTECH 是機構帳戶；繼續核對身分驗證、完整 App 清單、`io.woowtech.assistant` 的可用性、上傳權限和已使用版本碼。
2. 若尚未建立 App，先完成政策與出口聲明所需事實核對，再以正確帳戶及套件名稱建立草稿。組織帳戶需依 Console 實際狀態確認身分及聯絡資料。
3. 對最終 commit 建立可追溯 AAB，透過受控流程簽章，上傳內部測試軌，再由 Play 商店安裝至 POCO 驗證安裝、更新與核心功能。Google 允許內測最多 100 人；內測可能不經標準政策審查，不能視為正式上架通過。[內部測試](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en)
4. 完成 App content、Data safety、App access、前景服務、內容分級、目標對象、廣告、隱私政策與商店素材。表單答案必須依最終功能和實際服務確認。
5. 若為 2023-11-13 之後建立的**個人**開發者帳戶，Google 規定至少 12 名測試者連續加入封閉測試 14 天後才可申請正式版存取；是否適用以帳戶與 Console 狀態為準。[Google 個人帳戶測試規則](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en)

## 需要營運者確認的事

- 確認 App 建立狀態、可用上傳簽章方式及測試人員名單；**不要在聊天或倉庫提供私人金鑰**。
- 決定審查員可用且有額度限制的模型服務與安全交付方式。
- 確認正式檢舉由誰處理、伺服器與基礎設施的保存及刪除方式、隱私聯絡方式與可公開的政策網址；現有草稿的 30 天只代表程式設計或待確認內容，不等於正式環境已驗證。
- 確認商店版支援模型的內容安全處置、使用者報告的處理責任，以及外部 MCP 傳送資料的提示與告知方式。
