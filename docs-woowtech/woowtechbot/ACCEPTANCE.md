# Android 渥屋助理直裝版：實作與驗收（2026-11-26）

## 交付狀態

介面、服務容器與通知客戶端基礎已實作。原簽章 APK `0.1.37-woow.13`（3813）已在 POCO C85 / Android 15 覆蓋安裝並啟動。**這是待完成推播整合的候選版，不能視為整項需求驗收完成。** 未發布 GitHub release、未變更商店版部署。

基準：`2bb46820`；設計參考 `bc65d7b2`。僅 `woowtech` 直裝 flavor 啟用 `WOOWTECHBOT_ENABLED`。共用文件、草稿、服務／推播契約保留在既有共用模組，平台交付與 Firebase 依賴限定 Android 直裝 flavor。

已接入：全頁歷史與底部搜尋、名稱膠囊、四項對話選單、每對話名稱／機器人或本機圖片、獨立文字與附件草稿、原有快捷功能、完整網頁服務入口、每服務獨立 WebView Profile、服務切換與本機返回、通知設定、資料型通知驗證與路由。

## 實測結果

| 項目 | 結果與範圍 |
| --- | --- |
| 既有文件 core 測試 | `:core:test --tests '*document*'` 通過 |
| Android JVM | `:app:testWoowtechDebugUnitTest --tests '*Bot*'` 27 項通過（包含符合篩選的既有案例）；名稱／圖示、草稿／附件、搜尋、網址、registry 與 flavor gate |
| 通知 core | `BotPushTest` 9 項通過；契約、去重、延後路由、token 輪換及撤銷失敗重試以受控 API 測試 |
| 中繼 adapter | Node 11 項通過，使用假 sender；沒有真實 FCM 發送 |
| Firebase 設定轉換 | Python 5 項通過；僅接受 `io.woowtech.agent` 自有設定，拒絕其他產品或模糊 client |
| 真機 UI | `BotUiConversationDeviceTest` 3 項通過；名稱／圖示互不影響、取消不寫入、草稿還原、上傳圖片轉本機資料 |
| 真機 Profile | 2 項通過；同 origin 不同 Profile 的 Cookie／localStorage 隔離，清除一方不影響另一方；Android 實際 URI 的 LAN 判斷 |
| 真機通知 | `BotPushNotificationsTest` 5 項通過；注入合法資料後顯示一般提醒、SECRET 鎖屏可見度、同對話不同事件、拒絕未知服務／額外欄位、持久去重、撤銷通知；**不是 FCM 送達測試** |
| 真機 PDF 回歸 | 2 項通過；繁中多頁文件逐頁渲染、超大文件明確失敗 |
| 冷／暖啟動路由 | 用模擬通知點擊 Intent，冷啟動開服務 2，既有程序開服務 1；各自解析已保存 origin；本機返回可用。未驗證真實遠端 thread 權限與內容 |
| 參考服務連線 | 手機直接連 `192.168.2.10:18531/18532` 收到服務端 403；主機可收到 200。手機 shell HTTP 也收到 403，確認不是 WebView URL policy 導致。未繞過服務端限制 |
| Apporo 邊界 | 合併 manifest 沒有 bot activities/services、FCM receiver/service 或 FirebaseInitProvider；保留既有 ML Kit registrars。未執行 Apporo 商店發布或完整功能驗收 |
| APK／覆蓋安裝 | Release lint、六個必要 DEX 類別檢查、原簽章核對通過；`adb install -r` 成功，3811→3812→3813。appId 10315 與 firstInstallTime 保持不變；手機 APK SHA-256 與交付檔一致 |

正式包啟動與四項選單已實機確認。覆蓋安裝沒有解除安裝或清除資料；本輪沒有逐項讀取／比對既有全部對話、MCP 金鑰、記憶、技能、排程與瀏覽器資料，因此不宣稱完整資料庫內容逐項驗證。

## 尚未完成的必要驗收

1. 助理專用 Firebase 設定已包含於 3813 並覆蓋安裝；實際 FCM token 取得／更新、前景／背景／程序被回收後送達尚未驗證（見 [PaaS 真機紀錄](PAAS-DEVICE-QA.md)）。
2. v1 session discovery 與真實 HTTP registration/revoke adapter 已接入 bootstrap，14 項 HTTP fixture 與 9 項既有推播測試通過。lab 尚未部署新 capability，真機正確維持 SERVER_NOT_READY；真服務註冊／撤銷待驗。
3. WIF GCP 資源與精確 IAM 已實際建立且獨立唯讀核對通過，未建立 sender key。已通知 PaaS 開始 STS／impersonation 驗證；中繼部署與真 FCM 送達仍待驗，不以配置成功代替送達。
4. lab43/lab53 已完成普通 client 配對並保留登入。WebView thread/composer 空白仍未解決；網頁草稿、完整子頁返回、遠端檔案傳輸、登出與服務移除的伺服器撤銷仍待驗。
5. 未對所有既有原生功能做完整實機回歸；既有文件功能及本輪受影響的資料操作已做上述測試。

## 已知限制

- WebView 必須支援 `MULTI_PROFILE`；不支援時顯示提示，不共用登入資料。
- 返回歷史只存在程序記憶體；程序死亡重開服務首頁。草稿是否跨程序保留，取決於原網頁是否寫入 localStorage。
- 遠端頁面可用系統文件選擇器與同 origin 下載；blob 下載、遠端直接相機／麥克風／定位未支援。既有本機功能不由此容器代替。
- 離線登出立即隔離舊 Profile，但伺服器 session 撤銷失敗會明確告知；不能把本機清除說成遠端已撤銷。
- 通知 adapter 的記憶體 state 只供開發測試，不是可直接部署的持久化生產服務。

## 重現

使用 JDK 17 與既有 Android SDK。測試包需使用 `-PdevInstall`，避免碰到正式包名：

```sh
./gradlew :app:assembleWoowtechDebug :app:assembleWoowtechDebugAndroidTest -PwoowtechbotTests -PdevInstall --max-workers=1
./gradlew :app:testWoowtechDebugUnitTest --tests '*Bot*' -PwoowtechbotTests -PdevInstall --max-workers=1
./gradlew :core:test --tests '*BotPushTest' --max-workers=1
node --test tools/woowtechbot-push-adapter/adapter.test.mjs
python3 -m unittest discover -s tools/woowtechbot -p 'test_*.py'
python3 tools/woowtechbot/check_apk.py <APK>
```

真機 instrumentation 類別：`BotUiConversationDeviceTest`、`BotProfileIsolationTest`、`BotPushNotificationsTest`、`DocumentPdfTest`（完整 package 見各測試檔）。HyperOS 測試先用 shell 正常開啟測試 Activity，避免背景啟動限制；沒有更改 app-op。橫向輸入名稱後先收鍵盤，再捲動至圖示選擇。

曾捕捉到增量 DEX 輸出漏掉 `MikaApp`：清除此 worktree 的 debug project-dex 衍生快取重建後修復，且真機啟動及後續測試通過。`check_apk.py` 驗證 class definition，避免只搜尋 descriptor reference 誤判。

簽章設定由外部 `WOOWTECH_SIGNING_PROPERTIES` 提供；Firebase 設定由外部 `WOOWTECHBOT_FIREBASE_PROPERTIES` 提供。未提交任何金鑰或服務帳戶。APK 雜湊與版本見 [artifact.json](artifact.json)，服務與推播接線細節見 [INTEGRATION.md](INTEGRATION.md)、[PUSH-CLIENT-INTEGRATION.md](PUSH-CLIENT-INTEGRATION.md)。
