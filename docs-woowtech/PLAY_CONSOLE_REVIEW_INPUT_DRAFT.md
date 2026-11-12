# Google Play Console 審查資料草稿

狀態：**待完成、未提交**。正式收件端與 POCO Debug 版的送達、管理員讀取及使用者刪除已實測；最終簽署版本的 Play 軌道安裝仍待驗收。此檔不應包含 API Key、密碼、一次性驗證碼或完整私人端點。

## 建立 App 表單的候選值

這些值依目前產品決策準備；正式確認政策符合及出口聲明前，不代公司勾選或提交。

| 欄位 | 候選值 |
| --- | --- |
| 名稱 | 渥屋助理 |
| 套件名稱 | `io.woowtech.assistant`；須由 Console 驗證可用 |
| 預設語言 | 繁體中文 `zh-TW` |
| 類型 | 應用程式 |
| 是否收費 | 免費；發布後不能直接從免費改為付費 |

## App access 英文說明草稿

Only submit these instructions after a test provider has been provisioned and a reviewer can complete the steps from a clean Play installation. Supply credentials through the appropriate restricted Play Console field, not in source control or the public store listing.

> The app is free and the reviewer can open the app without creating a WoowTech account. AI responses require the test model service listed in the accompanying restricted credentials.
>
> 1. Open the app and complete the welcome screens.
> 2. Open model setup. Select the supplied official OpenAI, Anthropic, or Gemini provider, enter its model name and dedicated test API key, test and save it, then select it as the main model. Custom model base URLs are unavailable in this Play edition.
> 3. Start a new conversation, enter “Please reply with OK”, and send it. A successful response demonstrates the core AI chat.
> 4. To review reporting, long-press an AI response and select the report action. Select a reason and submit a clearly identified test report. Verify the reporter confirms delivery.
> 5. Memory, external MCP servers, voice input, and the in-app browser can be reached from the app’s navigation and settings. An external MCP endpoint is optional for the basic chat review; if its review is required, use the separately provided read-only test endpoint and instructions.

**Required before use:** confirm onboarding and labels against the final Play build; supply a working, rate-limited and renewable reviewer credential for one of the three official APIs, its model name, any locale or network requirements, support contact and expiry handling. Confirm that reporting actually delivers to an operated inbox, and provide test MCP credentials if the review requires that capability. Do not promise that a third-party sign-in or API key will be accepted by Play reviewers before verifying the process.

## 前景服務申報素材草稿

候選 AAB 的 merged manifest 顯示兩個 `specialUse` 服務；最終 AAB 仍須再核對。下列為準備影片與說明的提綱，不是 Google 已接受的用途。

| 功能 | 需要展示 | 待核對 |
| --- | --- | --- |
| 使用者啟動的 AI 任務 `TaskService` | 從 App 送出任務、顯示進度與通知、使用者停止、完成或中斷後的狀態。 | 前景服務何時啟動／停止、延後或中斷對使用者的影響；最終服務類型是否適合。 |
| 模型登入 `ChatGptSignInService` | 在 App 主動開始登入、切到登入畫面、回到 App、完成或取消，及服務通知。 | 是否有必要使用前景服務、實際可停止方式、延誤與中斷影響。 |

影片應使用最終候選版及測試帳號，遮蔽個資與憑證；先確認功能實際存在再錄製。Google 要求對申報的前景服務類型說明功能與延遲／中斷影響，並提供示範影片。[Google 前景服務說明](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)

## 其他 Console 欄位

- 隱私政策：雙語頁 `https://assistant-relay.woowtech.io/privacy/play` 已公開並有 App 內入口；在 Console 填入前核對最終 AAB 的資料流。
- Data safety：依 `PLAY_DATA_SAFETY_WORKSHEET_2026-11-12.md` 及最終模型、語音、附件、外部 MCP、檢舉與 SDK 的實際行為逐題填答。
- 內容分級、目標對象、廣告、AI 內容與其他聲明：依最終版本和 Console 題目逐項核實，不推測答案。
- 內部測試：待確定上傳簽章、版本碼及測試人員後準備；由 Play 安裝驗證不等於正式審核通過。
