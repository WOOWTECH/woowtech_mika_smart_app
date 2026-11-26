# Android Direct 原生 QR 驗收（2026-11-26）

## 實作與已驗項目

3820 一般包、diagnostics=false，原簽章覆蓋安裝；手機 APK 與交付檔 hash 相同，見 artifact.json。既有 lab43/53 profile 保留。原 PR47 已在所有必要 CI 通過後合併，merge ede3bb8299b0b489b04f50273d94793048bda160；本次 QR 為後續獨立修改。

原生服務頁選單新增「掃描配對 QR」，只在 WOOWTECH flavor 引入 Google Play services code scanner 16.1.0。掃描僅接受當前服務 exact HTTPS origin 的 /pair#code=…；不接受 query、其他目的地或額外 fragment。掃描結果只留記憶體，確認畫面僅顯示服務名稱與 origin，確認前不導頁、不兌換邀請。取消不發送配對請求。確認與非同步回傳重新核對 profile，拒絕過期操作。

POCO C85 / Android 15 實際開啟 Google 原生相機掃描畫面，顯示「由 Google 代表渥屋助理掃描」。2 項 QR 驗證測試（含 15 個拒絕案例）及 3 項 origin 測試通過；release 建置與 APK 6 類必要類別檢查通過。

## 尚未驗收

- 鏡頭實際讀取 QR、取消後無兌換，以及真正 HA 單次邀請配對，等待實際對準鏡頭；不能把掃描 UI 開啟當作成功掃碼。
- HA 新獨立 android-qa-ha profile 已建立，尚未配對；未產生短效邀請。需確認 HA 邀請 QR 格式，再於手機就緒時產碼。
- HA/Podman 通知、問題卡、鎖定返回、WebView 相機/系統檔案與附件尚待各平台測試。此掃描器不改 WebView 相機權限。
- 手機偵測一張 SIM（ABSENT,LOADED），但實際啟用行動數據並停 Wi-Fi 後無有效 default network，radio 類型 Unknown；已恢復 Wi-Fi 與行動數據原值。只能判定目前無可用行動連線，不能宣稱無 SIM 或不支援 cellular；Wi-Fi→cellular→Wi-Fi 續接未通過。
- 自然 AI 完成通知仍待 lab53 使用者模型登入；人工 fixture 不替代該項。

## 3819 推播補驗

人工 attention event c83af6d2-5c66-4abd-8218-f96facfdfd23：真機 tag 與原 lab53 service/bot/seed 相符，SECRET 通知本文點擊進 QA bot/composer；picker seed active、device 未選中。此為 3819 一般包實際收件與精確 seed 導頁，沒有模型呼叫。已回報 PaaS。
