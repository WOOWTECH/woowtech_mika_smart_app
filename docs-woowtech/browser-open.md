# 從瀏覽器開啟渥屋助理

2026-11-10：參照 Omnigent 對話 `332e571de0a048dc84c565719e1b01c4` 的 `resp_claude_283a2b89c80e1dfe4b1ac22b4b45bb9e`。舊版只有 launcher，實機解析 `io.woowtech.agent://open` 回傳 No activity found。現有線上頁面仍是 MAIN／LAUNCHER 的 intent，需另外換成以下連結。

正式入口：`io.woowtech.agent://open`，dev 入口：`io.woowtech.agent.dev://open`。

建議按鈕：

```html
<a href="intent://open#Intent;scheme=io.woowtech.agent;package=io.woowtech.agent;S.browser_fallback_url=https%3A%2F%2Faiot.woowtech.io%2Fopen-woowtech-agent%3Fv%3Dfb;end">開啟渥屋助理</a>
```

[完整網頁範本](../woowtech/web/open-woowtech-agent.html) 可交給原頁面部署方替換。LINE richmenu 保持 HTTPS 網頁入口；不應把 intent URI 直接放進 richmenu，也不應使用內部確認、付款或通知的 URI。範本不以頁面隱藏推定 App 已成功開啟、不自動輪詢跳轉；fallback 只顯示說明。GitHub stable 尚未包含此修正時，勿引導使用者下載 stable 並宣稱可以開啟。

瀏覽器入口只開啟本機 App，不選對話、不執行指令、不傳送訊息、不替使用者啟用無障礙，也不遠端解鎖手機。query、fragment、extras 全部不轉交。非 VIEW、其他 scheme／host、有 userinfo／port、其他路徑的直接 component 呼叫會結束而不開啟主畫面。

Chrome 要求 BROWSABLE，且可阻擋沒有使用者點擊的自動跳轉。因此以明確點擊為驗收主線；不能承諾 LINE 內建瀏覽器自動開啟。長期若需要 HTTPS 直接開 App，另實作 Verified App Links 與網站 assetlinks.json，不能僅加 manifest 就宣稱網域已驗證。

官方依據：[Chrome Android intents](https://developer.chrome.com/docs/android/intents)、[Android deep links](https://developer.android.com/training/app-links/create-deeplinks)。

## 驗證紀錄

POCO C85／Android 15，正式簽章、保留原資料覆蓋安裝：

- Chrome 真正點擊網頁按鈕：冷啟動（force-stop 後）與背景返回都成功。
- 背景返回使用同一個 Activity 與 task，未送出的草稿保持原文；測試草稿已清除，未送出。
- 帶 query、fragment、`open_conversation`／`prompt` extras：沒有切換對話，草稿不變。
- 直接指定 component 的六種非法輸入：錯誤 host、dev scheme、其他路徑、port、userinfo、MAIN action；均未開啟主畫面。
- `WoowtechManifestTest` 5/5；release 編譯及 lint 通過（0 errors、182 既有 warnings）；APK 品牌／入口檢查通過。
- 實際合併 dev manifest 的 scheme 為 `io.woowtech.agent.dev`；upstream manifest 沒有 BrowserOpenActivity。

本輪 Chrome 頁面由 USB reverse 提供 HTTP 測試站，點擊後經 Chrome 實際分派 intent；不是只以 `adb am start` 代替瀏覽器測試。負面輸入才由 ADB 指定 component，驗證 manifest 以外的程式防線。

尚未驗收：LINE 內建瀏覽器 A／B／C、未安裝時的實際 fallback、其他手機品牌。公開 `aiot.woowtech.io/open-woowtech-agent` 尚未替換，不能把本機通過宣稱為公開 LINE 選單已通過。

私有證據：`~/.local/share/woowtech-mika/test-evidence/browser-wake-20261110/`（reference-items、device-results、草稿前後與冷啟動 UI XML）。

## 候選版交付

- 原始碼：`3d419172`；正式簽章 APK 已覆蓋 POCO，最終檔再經 Chrome 按鈕驗證成功，手機 base.apk SHA 與候選檔一致。
- [下載頁與 HTML 範本](https://github.com/WOOWTECH/woowtech_mika_smart_app/releases/tag/v0.1.37-woow.4-browser.20261110)。獨立 prerelease，不替換 stable/latest；Android 版本仍是 `0.1.37-woow.4`／3804。
- APK SHA-256：`008da1f00978d846a533671980ab6cb623ced32aa1d97b89baa6049f0d664efe`。
- 測試 HTTP 服務與 USB reverse 已關閉；POCO 無障礙服務重新核對為 Bound，無 Crashed service。
