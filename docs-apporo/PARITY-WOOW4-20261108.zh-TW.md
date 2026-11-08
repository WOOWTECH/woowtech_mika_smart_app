# Apporo 對齊渥屋助理 woow.4

後續進度：woow.4 已合併至主分支 `1f96ab20`（與 `4ff45fc2` 相同 tree），Apporo 分支也已合併該主線。apporo.3 的修正與裝置驗收另見[第五輪報告](EMULATOR-WAVE5-20261108.zh-TW.md)與[第六輪報告](EMULATOR-WAVE6-20261108.zh-TW.md)；下列數據保留第四輪的原始範圍。

對齊基準是 `origin/woowtech/woow4` 的 `4ff45fc2bd8670f16351bcc210c41ddc02afa9d5`（PR #10），不是已發佈版本的保證。查核時 `origin/main` 仍為 woow.3 的 `5f957c1a`。使用者提供的 Omnigent 對話網址無法經網頁工具讀取，本輪以 Git 歷史與本機 `woow4/REPORT.zh-TW.md`、`woow4-followup/REPORT.zh-TW.md` 核對實際變更與驗收範圍。

## 程式對齊

- 完整合併 woow.4 分支，保留其提交歷史。共用修正包含同意通知金額放入標題與內文前方、通知分類名稱在啟動／語言切換時更新且保留使用者自訂設定。
- 準時提醒的權限原本只有 woowtech flavor；新增 `app/src/apporo/AndroidManifest.xml`，Android 13+ 宣告 `USE_EXACT_ALARM`，`SCHEDULE_EXACT_ALARM` 限 API 32。上游 manifest 不變。Apporo 原始碼檢查及 APK 檢查均守住這兩項宣告。
- Apporo 版本升為 `0.1.37-apporo.2`／3802，供 apporo.1 覆蓋升級驗證。獨立簽章、套件、更新網址與資料目錄不變。
- 補上 Apporo 繁中權限錯誤指引的「應用程式存取」名稱，與實際設定頁一致；原先沿用上游的「應用訪問」。原始碼檢查會核對指引與頁面名稱。
- 保留 Apporo 英文預設、金色視覺、App 主題標誌、初始膠囊置中及 aiot／platform／smart 產品脈絡。這些是品牌差異，不是功能缺漏。

第四輪驗收的程式提交為 `987588a1`。共享 CI（42429764916）、Apporo 建置（42429764915）及 WOOWTECH 建置（42429764928）皆通過。新 APK 裝置結果另由第四輪模擬器報告記錄，不能由 CI 成功推論。

## 驗證範圍與界線

本機 Apporo 資源／格式／權限檢查通過，CLI 58 項測試通過；WOOWTECH 品牌來源檢查與服務端點檢查通過。完整共享 JVM、Android、Python CLI、Go relay 測試與雙品牌建置均由 CI 通過。成品權限檢查的負向驗證也通過：舊 apporo.1 因缺少 USE_EXACT_ALARM 被新檢查拒絕。

第四輪已驗證：apporo.1→apporo.2 資料保留、同意通知金額、一次核准僅送出一次、拒絕不送出、付款接手、準時提醒、通知名稱切換，以及 momo／蝦皮的 Assistant 自主操作。既有第三輪僅手動操作購物 App／Chrome，不拿來代替自主能力。

使用者已授權沿用渥屋助理測試設定。本輪私密讀取既有 LiteLLM 設定；`model-preflight.json` 只證明列表有 54 個模型及原指定名稱，不含金鑰。實際完成請求時，`chatgpt/gpt-6.1-sol` 回覆帳號不支援，因此改用同一閘道已通過實際呼叫的 `apporo/gpt-6.1-sol`。模型路由差異必須與 App 功能差異分開，不宣稱與渥屋先前使用相同路由的速度／答案逐字一致。先前金鑰曝光的輪替建議仍有效；沒有把已驗證可用的帳密自動解讀成已完成輪替。

## 第四輪結果

逐項方法與證據見[第四輪模擬器報告](EMULATOR-WAVE4-20261108.zh-TW.md)。

| 項目 | 本輪觀察 |
| --- | --- |
| 覆蓋升級 | apporo.1 → apporo.2，對話標記、模型設定、繁中及深色保留。USB 手機小幫手在 APK 替換後需重新執行新版啟動腳本；首次 momo 任務因此如實停止，不能把這一段略去。 |
| 通知分類 | 五個實際存在的分類隨英文／繁中切換，自訂 importance=2 與 userLockedFields=4 保留，測完恢復。 |
| 準時提醒 | 預定 08:49:19.000，enqueue 08:49:19.092，發聲事件 08:49:19.309；橫幅可見、沒有 SILENT。這不是實體聲音聽測。 |
| 一次同意 P1 | 收合橫幅內文可見 NT$590，同意一次後測試商店 FINAL=1，沒有重複。 |
| 拒絕 P8 | FINAL=0，時間軸顯示 You declined，沒有標 Worked。模型主動先問，沒有強制測試未核准 Enter 工具呼叫。 |
| 付款接手 P5 | Needs you: Payment NT$500；只有 Skip／I will handle it／Cancel task，沒有一次允許付款按鈕；Skip 後 FINAL=0。 |
| momo 自主搜尋 | 小幫手恢復後約 4 分 38 秒／13 步，前三筆價格 2290／7490／550、第 1 與 3 筆 Ad 與獨立畫面一致；第三筆長品名尾端被截斷，未宣稱核對全文。 |
| 鎖屏核准 | 解鎖前新增 FINAL=0；解鎖後新增 1。預設允許敏感內容時金額可見；臨時 PIN 已刪除。 |
| 蝦皮網站 | 登入／滑塊驗證阻擋，Assistant 如實交接、沒有編造價格；商品搜尋未通過。 |
| smart | 真實配對後自主讀兩個專案與 README，44 秒；既有待確認修改請求保留，本機連線已移除。 |
| aiot | 真實登入、臨時裝置註冊後自主讀 Overview，35 秒；可見數值與獨立截圖一致。只做唯讀；自建裝置已刪、權杖撤銷，原有 18 筆裝置保留。 |
| PChome | 自主搜尋 75 秒；同一桌面版結果的前三筆 999／988／988 與獨立畫面／DOM 一致。第一筆為兩件組，不混同單件；行動版排序不同。 |
| Universal APK | arm64 模擬器覆蓋安裝及全新安裝均啟動成功，versionCode 3802，USE_EXACT_ALARM 皆已授予；不代表其他 ABI 已執行驗證。 |

實體聲音、Android 12–15、其他手機廠牌、platform 舊帳號被拒、正式發佈簽章／更新管道仍是獨立限制。woow.4 本身也沒有完成所有 Android 版本及實機聲音驗收，因此不能用程式相同來聲稱所有環境效果一致。鎖屏內容會受系統的敏感通知設定影響，不能無條件宣稱金額永不出現在鎖屏。

## 收尾

本輪模擬器時段 08:34:45–09:43:52，約 69 分鐘。新增 App、臨時 PIN、連線與測試伺服器已清除，原有套件清單一致；審查主機恢復 healthy、SLOT_EXIT=0、HEAVY_EXIT=0，heavy free、無殘留 qemu。Apporo 審查主機全程持續運作。APK 為獨立測試簽章成品，尚未正式發佈。
