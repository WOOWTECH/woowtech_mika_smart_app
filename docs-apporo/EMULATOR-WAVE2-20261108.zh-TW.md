# Apporo Assistant 第二輪模擬器驗收

日期：2026-11-08。第一輪見 [既有驗收報告](EMULATOR-20261108.zh-TW.md)。本輪補實際 Apporo 產品入口、英文畫面與浮動膠囊；沒有把登入前檢查寫成登入後整合通過。

## 環境與證據

- Android 16 / API 36，arm64，1080×2400，系統英文、字體1.0。
- Assistant package `com.apporo.assistant`；起始來源 `5dd8a37c`，膠囊位置修正版 `2ca8edbc`（CI 合併建置 `6ce68a3`），版本仍為 `0.1.37-apporo.1` / 3801。
- 使用獨立本機測試簽章，不是正式發行版。APK 品牌、package、語系標籤、runtime 身分與更新隔離檢查通過。
- 證據根目錄：`~/.local/share/apporo-assistant/test-evidence/emulator-20261108-wave2/`。
- 模型沿用已授權 LiteLLM 測試服務。沒有真實付款、設備控制或業務資料修改。

## 實際產品入口

| 產品 | 安裝來源與身分 | 實際結果 |
| --- | --- | --- |
| Apporo aiot | 官方 repo CI 38421929349，`com.apporo.aiot.minimal.debug`，`2026.10.3-beta.0.40+cecd492-minimal` | 成功安裝、歡迎頁、探索主機與手動位址頁。Assistant 實際操作後正確讀出「What is your Apporo aiot address?」、位址示例及 Connect，沒有輸入主機或憑證。證據 `apps/06-aiot-agent.json`、`07-aiot-manual.xml/png`。 |
| Apporo platform | 官方 repo CI 42420769389，`com.apporo.odoo.debug`，`1.0-debug` / 8 | 成功安裝並開啟。Assistant 正確讀出 Server URL、Database Name、Next，並說明此頁尚無帳密欄位。與獨立截圖一致，未按 Next。證據 `apps/10-platform-login.xml/png`、`12-platform-agent.json`。 |
| Apporo smart | 從既有發版收據追到外接碟 AAB，轉 universal APK 並以獨立測試金鑰簽署；`com.apporo.smart`，0.8.1 / 8001 | 成功安裝。`apps/21-smart-settled.xml/png` 顯示 Welcome to Apporo smart、Scan QR code、Direct connection、Paste pairing link、Settings。Assistant 已實際進入 Direct connection，讀出 Host、Port 6772、SSL、Password 與進階 URI，返回歡迎頁；`23-smart-agent.json` 與獨立 `24-smart-direct.xml/png` 相符。不是 Play 安裝或正式簽章驗收，尚未配對主機。 |

aiot 啟動修正是測試方法：Android 16 必須帶 MAIN action 與 LAUNCHER category；單用 `am start -n` 可能被 intent filter 擋下。第一輪「舊 APK 無法解析 Activity」不足以判定 App 壞掉。本輪目前的 aiot APK 用正確 intent 可正常啟動。

繼續登入所缺的資料：aiot 的實際主機 URL、是否需要 VPN／區網、允許查閱的測試房間；platform 的實際 URL、資料庫名稱及允許查閱的專案／任務。密碼由使用者在交接畫面輸入，不放報告或對話。

smart 需要指定電腦及其配對方式，直接連線要知道 host、port、SSL 與是否要求密碼。這次是既有0.8.1 AAB，不能據此宣稱較新桌面0.9.0或商店目前版本已驗過。另在 smart 自己的對話框讀到「a Apporo smart server」文法錯字，屬 smart 產品文字，不是 Assistant 回答自行杜撰。

## 浮動膠囊

已重現可見膠囊與 Android 開發人員選項右上角搜尋重疊。視窗大小約147×147；證據支持可見控制項重疊，未證明是透明大視窗攔截。把膠囊移到側邊中段後，搜尋可操作。

`2ca8edbc` 增加可選的品牌預設高度 `capsule.default.fraction`；Apporo 設0.5，上游／渥屋預設仍為0。已拖曳的位置優先，不用更新重設使用者偏好。品牌值解析、範圍處理及儲存位置保留的測試通過。

- 覆蓋更新：`overlay/14-upgrade-model.xml` 確認原主模型、看圖角色、54 models 與深色設定保留。`13-upgrade-capsule.png` 確認原本拖到頂端的位置保留。USB helper 更新後重新執行啟動腳本；本輪不宣稱更新後無須恢復手機操作。
- 乾淨安裝：`overlay/19-fresh-search.png` 顯示膠囊在側邊中段；`20-fresh-search-settled.xml/png` 確認右上角搜尋實際開啟。
- 限制：仍可自行拖回工具列上；不是全面禁止遮擋，也不是點擊穿透功能。
- 新發現與修正：App 強制深色、系統淺色時，標誌仍取淺色 drawable，灰色圖案落在深色膠囊上。`3171e5c2`（CI 合併建置 `7e72140`）改用 App 主題決定 Apporo 單色標誌；其他品牌不套色。已安裝複測：`overlay/24-dark-logo-settled.png` 為深色膠囊白色標誌，`26-light-logo-settled.png` 為淺色深灰標誌，`27-system-dark-app-light.png` 為系統深色／App 淺色。標誌隨 App 主題，未被系統 drawable-night 反轉。

## 英文介面巡檢

`ui/` 記錄模型角色、context、Token 用量、語音設定、任務執行與步數限制、通知、App 存取、代理、計算環境、外部 MCP 新增表單、電腦連線 USB／Wi-Fi／遠端／進階、關於、更新記錄、記憶、技能、待確認、網站登入、操作路線、排程、瀏覽器、語言、深色、手機操作、恢復及自我檢查入口。

檢查方式為 UI 節點與實際截圖交叉確認；表單未儲存的測試設定不算服務連線通過，空清單也不算有資料時的全狀態驗收。英文頁的語言選項「繁體中文」是語言名稱，不是漏翻。內部協定名 `mika connect` 保留。

- 授權頁完整捲到最後，86個元件、Mika、Google ML Kit 與 GPL runtime 說明都有保留。`licenses/sweep-01`～`24` 與 montage 可核對，末幾張是重複底部。
- 深色語言頁 `ui/31-dark.png`、設定 `32-dark-settings.png`、對話 `35-dark-chat.png` 與模型／恢復頁已留證。
- 1.5倍字體補驗 `ui/42-large-settings.png`、`43-large-model.png`：主要列可操作，模型長名稱省略顯示；不是所有畫面的大字體驗收。`44-updated-recovery.xml/png` 已在新 APK 確認「an Apporo Assistant update」，補上第一輪最後文字修正未裝機的缺口。
- `ui/33-dark-chat.png` 實際是返回後露出的 aiot；`34-dark-main` 是側欄。這兩個檔名不能當對話頁通過證據。`37-recovery` 最初誤拍設定頁，已覆寫為正確恢復頁。
- uiautomator 會短暫解除無障礙服務，dump 的「Not running」不單獨判故障。執行任務中改用截圖與系統日誌。主螢幕的 adb input 明確指定 `-d 0`，避免輸入到虛擬螢幕。

## 背景同意通知補驗

來源 `2ca8edbc`：先完成 Python 計算，保留 Task done 通知，再從手機交辦本機假商店 NT$590 訂單並立即回桌面。`notify/approval.mp4` 錄到 Needs your OK: Place order 橫幅；`notify/banner-contact.jpg` 是從影片55秒起每秒取樣的接觸表，可核對橫幅連續出現。06:49:04.959 的通知事件為 beep=1、mute_reason=0。同意通知屬 `attention.0`，沒有被系統改成 SILENT。

從通知欄按 Decline，回答確認沒有送出、沒有繳費代碼；`notify/server.jsonl` 整輪 FINAL=0。`07-shade.png` 展開通知可看到金額；收合橫幅仍會截掉金額卻有 Approve，這個繼承的已知問題並未在本輪修改。系統日誌不代表實體喇叭測試。

## 測試憑證事件

重新設定模型時，鍵盤引發欄位移動，測試金鑰誤填入網址欄，隨後工具的畫面診斷輸出帶出金鑰。已清掉錯誤網址，改以欄位標籤輸入並確認 password 欄位；本輪保存的文字證據掃描沒有金鑰。已向使用者說明需要撤銷換新。工具輸出中的洩露不能因本機檔案乾淨就視為已消除。

## 尚未證明的部分

實際 Apporo 主機登入、登入後資料、smart 配對工作階段、全部畫面全部狀態、實體手機聲音與廠牌省電行為，仍未完成。模擬器提示音事件不等於實體喇叭驗收。正式簽章與公開更新頻道也未建立。

實機聲音驗收要準備可側載的 Android 手機、已授權模型與通知權限，先確認通知音量大於0、勿擾關閉。保留一則完成通知，在 App 背景交辦同一份本機假商店案例，核對橫幅、聲音及拒絕後零訂單；再測有／沒有精準鬧鐘權限的提醒，分開記錄預定與實際時間。最後補鎖屏、省電模式及該廠牌背景限制。不要以真實購物或設備控制作聲音測試。

## CI 與收尾

程式提交 `3171e5c2` 的共用 CI（42421956657：JVM、Android、Python CLI、Go）、Apporo 建置（42421956536）及渥屋建置（42421956488）全部成功。修正版已簽成獨立本機測試 APK 並安裝驗證；檔案雜湊見 `artifacts.json`。這不代表正式簽章發行。

時段06:16:39～07:01:11，約45分鐘。已撤銷電腦存取、清除 adb forward/reverse、移除本輪手機錄影、還原 Gboard／字體1.0／系統淺色，解除安裝 Assistant、aiot、platform、smart 與 ADB Keyboard。原有 `io.woowtech.smart.debug` 保留，Apporo/helper 程序清單為空；假商店已停止。`cleanup/` 保存讀回，`slot/slot.log` 確認 holder exit0、模擬器停止、review host healthy。

最後保存的文字證據掃描為0個金鑰命中，見 `credential-scan.json`；這不撤回先前工具輸出的洩露，也不取代撤銷換新。沒有發布 APK 或合併 PR。
