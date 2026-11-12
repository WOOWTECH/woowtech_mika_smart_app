# 商店版 AI 檢舉營運流程

適用：`io.woowtech.assistant`。正式收件端為 `assistant-relay.woowtech.io`。本文件不含任何權杖或使用者檢舉內容。

1. 負責人每日在受信任電腦執行 `python3 tools/woowtech-relay-worker/scripts/review-ai-reports.py`，檢查新檢舉並記錄處理結果。權杖只放在權限 `0600` 的本機私有檔，不能貼到聊天、網址、瀏覽器、公開 CI 或日誌。
2. 依回覆內容、原因與補充說明評估是否涉及 Google Play 禁止內容；若有，先處理內容風險，確認模型／提示詞／過濾器的修正與回歸測試。檢舉不是自動判定，勿只根據單一文字關鍵字封鎖。
3. 使用者可在 App 的同一則回覆檢舉畫面刪除已送達、持有刪除憑證的紀錄。若沒有憑證或使用者以信箱提出請求，負責人核對檢舉編號後可執行 `python3 tools/woowtech-relay-worker/scripts/review-ai-reports.py --delete UUID --confirm UUID`。若需核對身份或範圍，透過隱私聯絡信箱回覆，避免向未授權者洩露檢舉內容。
4. 收件端在報告建立後 30 天停止管理員讀取；Durable Object alarm 每小時清理到期報告及 IP 計數。自動測試已驗證到期與未到期項目的清理邏輯，正式環境需持續監看 alarm 與錯誤；沒有經歷完整 30 天的現場等待測試。
5. 不將原始檢舉內容複製到工單、公開 issue、測試資料、模型提示詞或分析服務。若需用於回歸測試，先去識別並縮小到必要片段。

公開政策：<https://assistant-relay.woowtech.io/privacy/play>。營運聯絡：`woowtech@designsmart.com.tw`（與現有 Play Console 機構帳戶的聯絡資訊一致；需由負責人確認此信箱確實接收隱私請求）。
