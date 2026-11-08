# Apporo 第三輪模擬器手動驗收（2026-11-08）

這輪在使用者明確授權「持續監控，環境可用即開始」後執行。07:30 首次檢查時，原 `release-woowtech-agent-followup-1108` 已釋放：heavy lock free、qemu 不在、渥屋審查主機 `/api/health` 回 200、AC 供電、磁碟可用 21 GiB、可用記憶體 58%。沒有修改上一輪的心跳或 done。

使用 `release-slot.sh` + `holder.sh 60` 開啟 `release-apporo-wave3-1108`，07:30:41 開始、07:31:28 開機就緒。Apporo review demo 全程維持運作。本輪唯一畫面操作員以手動 ADB/UI 操作驗證；**沒有使用模型金鑰、沒有執行 Assistant 自主任務，所以不能宣稱購物或產品整合的自主能力已通過。**

證據根目錄：`~/.local/share/apporo-assistant/test-evidence/emulator-20261108-wave3/`。`monitor-status.json` 記錄狀態與收尾；`results.json` 為案例索引。以下相對路徑均在證據根目錄。Android 16/API 36，arm64，1080×2400，Chrome/WebView 133.0.6943.137。

## 結果

| 案例 | 結果 | 實際範圍 |
| --- | --- | --- |
| SHOP-01 momo Android | 手動通過 | 安裝 2502.2.0 四個 split，略過非強制更新、拒絕通知、關閉新手提示，無登入搜尋「無線藍牙耳機」，核對前三筆名稱、價格與 Ad。 |
| SHOP-02 momo web | 手動通過 | Chrome 開官方搜尋，按「繼續使用網頁版」，讀到「象印 保溫瓶 480ml」前三筆。 |
| SHOP-03 Shopee web | BLOCKED | 初次有語言選擇；另一搜尋分頁轉 `/verify/traffic/error`，確認語言後顯示「請登入」。沒有商品價格可核對，未繞過、未登入。 |
| SHOP-04 Shopee APK | NOT_RUN | 既有包僅 32 位元，不適用此模擬器；未安裝。 |
| SHOP-05 PChome web | 手動通過 | Chrome 實際呈現搜尋結果，前三筆可見名稱與價格。 |
| SHOP-06 同規格比價 | 未通過完整驗收 | 各站前三筆型號及組合不同，蝦皮無結果；沒有宣稱哪站同規格最便宜。 |
| SHOP-07 登入接手 | 手動觀察完成 | 已保存蝦皮實際登入阻擋頁；沒有 Assistant 接手卡或回答驗收。 |
| SHOP-08 知識／時間軸 | NOT_RUN | 無模型任務，因此沒有新的時間軸或 App 知識使用證據。 |
| smart Android 配對／讀取 | 手動通過 | 既有安全配對檔 → relay → 兩個專案 → 開啟既有 workspace → Explorer → README 預覽。 |
| aiot Android 認證 | 手動通過 | 既有 demo 主機與帳密，登入後到「How would you like to name this device?」。 |
| aiot 儀表板 | NOT_RUN | 下一步 Save 會註冊手機；為遵守本輪唯讀／不修改伺服器資料範圍，沒有送出。不得把認證成功算成 dashboard 通過。 |
| platform | NOT_RETRIED | 已知舊帳號 AccessDenied，本輪未重試、未安裝。 |
| Assistant 模型與自主執行 | BLOCKED | 安裝既有 `3171e5c2/apporo-test-arm64.apk`；英文 welcome → Set up a model，未填金鑰，Next disabled。未繞過 onboarding。 |

## 購物畫面核對

價格是 2026-11-08 約 07:33–07:46 的畫面觀察，不是固定商品資料或付款報價；促銷、條件與排序可能改變。沒有加購物車、下單或付款。

momo App：`shopping/08-momo-results.xml` 加 `shopping/11-momo-guide.png`（此圖實際已關閉提示、顯示完整列表；已人工看圖）。

| 順序 | 商品 | 畫面價格 | 限制／廣告 |
| --- | --- | --- | --- |
| 1 | Anker soundcore Liberty 4 NC 降噪真無線藍芽耳機 | NT$2,290 | Ad；劃線價 5,200 |
| 2 | Samsung Galaxy Buds4 Pro 真無線藍牙耳機（R640） | NT$7,490 | 「下單再折」；本列未見 Ad |
| 3 | Philips 飛利浦強力低音入耳式無線藍牙耳機 TAT1109 | NT$930 | Ad；劃線價 1,380 |

第三筆與渥屋舊測試不同，使用本輪觀察，沒有沿用舊答案。XML 的價格含格式替代字元，價格以截圖目視核對。

momo 網頁：`shopping/42-momo-web-settled.png` 已人工看圖，`shopping/40-momo-web.xml` 可核對完整商品文字。從 `https://m.momoshop.com.tw/search.momo?searchKeyword=…` 轉至官方 `momoshop.com.tw/search/…` 行動版。

| 順序 | 商品組合 | 畫面價格 |
| --- | --- | --- |
| 1 | 象印買一送一旋蓋 480 ml，SM-JF48 + SM-JF48 | NT$999 |
| 2 | 象印買一送一彈蓋 480 ml，SM-SR48E + SM-SR48E | NT$1,177 |
| 3 | 象印買一送一旋蓋 480 ml，畫面型號顯示 SM-ZB48E… | NT$1,177 |

畫面有「滿1111折111」、折價券、登記／贈品等標示，沒有推算結帳價。完整名稱可能在畫面截斷；XML 文字與可見字樣分開看待。

PChome：`shopping/31-pchome-results.png` 已人工看圖，官方網址 `https://24h.pchome.com.tw/search/象印%20保溫瓶%20480ml`。

| 順序 | 可見商品／型號 | 畫面價格 | 條件 |
| --- | --- | --- | --- |
| 1 | 象印超輕量不鏽鋼彈開式保溫杯 480ml+480ml（SM-SR4…，截斷） | NT$999 | 任選1件999、售價已折；未進詳情確認完整型號 |
| 2 | 象印彈蓋漸層款 480ml（SM-VH48） | NT$988 | 滿1000折100 |
| 3 | 象印彈蓋 480ml（SM-WJ48） | NT$988 | 滿1000折100、售價已折 |

這些卡片未見 Ad 標示，但不等於證明平台沒有付費排序。PChome 後續 dump 只讀到瀏覽器外框，不能因此說畫面沒有商品；這裡的價格證據是截圖。沒有抓取不可見規格來補齊同規格比較。

Shopee：`shopping/27-shopee-error.png` 已人工看圖，顯示「看起來您尚未登入。請登入以繼續，或返回首頁。」只有登入與返回首頁按鈕。原始分頁再次顯示語言選擇（`29-shopee-original-settled.png`），沒有把分頁標題含搜尋詞當成商品結果。官方搜尋入口：`https://shopee.tw/search?keyword=象印%20保溫瓶%20480ml`。

## smart 與 aiot

smart 使用既有測試簽章 APK 0.8.1，不代表 Play 商店最新版本。`smart/05-projects.png` 顯示 `apporo-home-dashboard`、`apporo-site-demo`；`smart/06-project-open.png` 顯示既有 demo agent 正等待修改批准，沒有點 Allow／Reject／Stop。`smart/09-readme.png` 成功顯示 Apporo Home Dashboard 的 README（470 B，20 lines），文件說明、目錄與開發指令皆可見。沒有建立工作區、送代理訊息、執行程式碼或改檔。測後使用 Hosts → Remove，確認刪除本機 saved connections；`smart/15-unpaired.xml` 僅剩 App 設定與 Add host。沒有撤銷共用 demo 配對身分、沒有重啟遠端主機。

aiot 使用 `app-minimal-debug.apk`。從歡迎頁 → 手動位址 → OAuth 登入，帳密僅經 stdin 傳入。首次以 Tab 移動欄位，密碼欄身分檢查失敗時立即停止，沒有輸入密碼；重新點選、驗證 password + focused 後才輸入並送出。`aiot/06-after-login.png` 是登入後命名裝置頁，不含登入資訊。未按 Save、未授予感測器權限、未控制任何設備。

收尾曾檢查本輪新裝 App 的私有 DB，`servers` 為 0 列，無已儲存 refresh token、webhook 或 device registration。`aiot/revoke.json` 記 `revoked_tokens=0`，**不能宣稱已撤銷一把登入 token**；未完成 onboarding，已停止並移除 App，亦未證明伺服器端是否存在短期 OAuth flow。未為查詢此事額外登入或修改共用帳號工作階段。

## 限制與收尾

- 沒有模型呼叫：先前曝光的 key 完全未讀取／未使用。需要確認替換金鑰後，才能跑 Assistant 自主購物、服務操作與時間軸驗收。
- aiot 需要可註冊測試手機且可清理的隔離測試範圍，才能繼續登入後 dashboard；本輪止於認證。
- 不代表實體手機聲音、所有畫面、所有服務與渥屋助理效果完全一致。
- 只寫本報告與本機證據；沒有改產品程式碼、沒有 commit／push。
- 起始第三方套件只有 `io.woowtech.smart.debug`。本輪新裝 momo、ADB Keyboard、Apporo smart、aiot、Assistant，收尾皆已移除，原有渥屋 smart 保留；`packages-before.txt` 與 `packages-after.txt` 相同。
- Chrome 新開的四個分頁已關閉，原有 Google 與 GitHub 兩頁保留；`shopping/54-chrome-two-tabs.txt`。網站正常瀏覽產生的 cookies／history 未整批清除，以免影響既有資料。
- Gboard 已還原；ADB forward／reverse 均為空。本輪沒有啟用手機 helper、無障礙或 Assistant 電腦存取。
- `crash-summary.json`：本輪 crash buffer 0 行。這是有限檢查，不等於全系統無任何錯誤。
- `credential-scan.json`：58 個本輪文字檔查不到已知 aiot 密碼及 smart 配對連結；未聲稱圖片做過 OCR 掃描。登入／配對資料出現時未截圖，完成／清除後才留證。
- 07:47 送本輪 DONE，07:48:07 holder 收到，07:48:08 模擬器關閉，總時段約 17 分 27 秒；`HEAVY_EXIT=0`、`SLOT_EXIT=0`、`review host healthy`，qemu 為空、heavy lock free。Apporo 示範主機仍是原啟動時間，未中斷。
