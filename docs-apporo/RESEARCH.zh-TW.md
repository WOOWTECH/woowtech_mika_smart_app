# Apporo Assistant：產品研究、功能對照與實作決策

研究日期：2026-11-07。基底：`5f957c1a`（Mika 0.1.37／渥屋助理 woow.3）。分支 `apporo/assistant`。
本文件區分程式已有能力、品牌實作與待現場驗證的整合，不把官網介紹當成助手的實測結果。

## 1. 產品定位與內容框架

Apporo Assistant 是英文優先的 Android 行動助手：協助使用者理解空間狀態、協調工作、研究資訊、完成手機與文件任務。
保留 Mika 的一般用途，並以 Apporo 的空間與工作情境作為引導入口。
暫採「場域管理與日常工作兼顧」，等待使用者對主要受眾的回覆。

核心敘事：**Your spaces. Your work. Your next step.**
內容分成四個入口：

| 入口 | 使用者想完成的事 | 能力來源 |
| --- | --- | --- |
| Spaces | 查看會議室狀態、辨識離線設備、整理觀察 | 手機操作＋Apporo aiot 畫面 |
| Work | 整理指派任務、逾期事項與交接資訊 | 手機操作＋Apporo platform；帳號可見範圍 |
| Research & files | 比較設備、閱讀文件、計算與報告 | 瀏覽器、檔案、沙盒、模型 |
| Follow-through | 提醒、週期任務、電腦協作、接手 | 排程、通知、CLI／MCP、Apporo smart |

這些是既有介面中的文案與範例分類，尚未新增四分頁導覽。先保留成熟的對話、側欄和設定流程，避免品牌重作破壞操作能力。

回答框架：結果 → 依據 → 尚未完成／需要接手的事項。缺資料時說明缺什麼，不以品牌行銷取代事實。
首頁範例先做唯讀狀態整理；實際控制設備與修改紀錄仍依使用者要求與原本確認機制處理。

## 2. Apporo 三款產品的差異與可重用做法

| 產品 | 已有架構 | Assistant 的角色 | 不應混淆的地方 |
| --- | --- | --- | --- |
| Apporo aiot | Home Assistant 衍生 App；`com.apporo.aiot` | 操作已連接場域的實際儀表板 | 不等於 Assistant 內建所有設備協定；儀表板依主機而異 |
| Apporo platform | Odoo 衍生 App；`com.apporo.odoo` | 查閱帳號允許的業務模組與紀錄 | 不保證每台伺服器都有維修、庫存、專案模組 |
| Apporo smart | 共用 smart 程式的品牌版本；`com.apporo.smart` | 查看已配對主機與工作階段，按指定範圍交辦 | 不等於手機直接有電腦檔案權限；禁止無限互相委派 |

aiot 早期獨立 fork 有重複維護與文案漂移；platform 的 Android flavor、smart 的集中品牌設定較適合長期同步。
本次沿用同程式碼、多品牌建置。獨立 package 讓兩款助手可並存，資料與權限由 Android package 邊界隔離。

現有 Apporo smart 品牌設定：主色 `#8B6B24`、深色強調色 `#C49E53`、圖示底色 `#4D4D4D`。
沿用官方向量的路徑幾何，採灰底白標的 launcher；介面主色採金棕，不改寫成功／錯誤的語意色。
名稱在所有語系保留 Apporo Assistant；法定品牌署名 APPORO UNION INC.，Mika 原作者與授權保留。
Apporo 舊產品政策不直接充當新助手的政策，因為螢幕內容、模型供應商與操作權限的資料流不同。

## 3. Mika／渥屋助理功能對照

| 能力 | 現有來源 | Apporo 方案與實際限制 |
| --- | --- | --- |
| 對話、附件、語音 | `app/.../ui`、模型／語音設定 | 共用；英文預設，可選繁中；模型仍由使用者設定 |
| 模型與服務商 | `app/.../settings/ProviderPresets.kt`、`core/.../model` | 保留多角色模型與自訂相容服務；未綁定品牌付費模型 |
| 手機 App 操作 | `app/.../cap/phone`、`core/.../phone` | 共用虛擬螢幕、觀察、點按與輸入；需手機操作設定與裝置相容性 |
| 無障礙／配對恢復 | 手機 setup、helper、recovery | 繼承 woow.3 修復；Apporo package 須另外實測配對、重開機與解除安裝 |
| 網頁研究 | `app/.../cap/web`、web 工具提示 | 保留分頁、閱讀、表單與瀏覽；Google 搜尋；網站登入與封鎖照實交接 |
| 文件與計算 | sandbox、`run_command`、檔案工具 | 保留運算與匯出；輸出資料夾 Apporo Assistant |
| 記憶與技能 | `core/.../memory`、`skills` | 保留確認／學習流程；英文為預設輸出；不存憑證 |
| App／網站知識 | `core/.../knowledge` | 新增三款 Apporo APP.md；僅描述已知產品關係，未知版面需觀察 |
| 排程與提醒 | TriggerRuntime、排程工具 | 保留；精準程度受權限與系統限制，不能承諾無權限也準時 |
| 同意／接手／取消 | ConfirmationGate、TaskService、AlertGroup | 繼承 woow.3；不能因 Apporo 身分降低付款與遠端任務限制 |
| 電腦 CLI／MCP | `tools/mika`、remote、mcp | 保留協定名；增加 Apporo package 與版本辨識，並存時明確選 package |
| 遠端閘道 | RelaySection、relay | 使用者自己設定；沒有部署 Apporo Assistant 閘道或復用 smart 的服務 |
| 自我檢查與診斷 | `app/.../about` | 共用檢查；Apporo 診斷抬頭；不可把「連線成功」當成所有能力通過 |
| 更新與安裝 | UpdateChecker、ApkUpdater、ApkIntegrity | 獨立 Apporo 更新來源；不得下載渥屋 APK；首發渠道尚未建立 |
| 授權與來源 | BrandLicenses、licenses、GPL runtime | 保留 Mika／ML Kit／runtime 說明；正式發行仍須對應 GPL 原始碼附件 |

「功能共用」是程式結構結論，不是 Apporo APK 的實測通過證明。

## 4. 官網與能力邊界

[Apporo 官網](https://www.apporo.ai/) 的定位包含智慧空間、視覺管理、系統整合、維運、能源與 AI。
Assistant 將其轉成具體工作場景；不把整個平台的硬體、備份、協定、預測分析或資安宣稱直接寫成助手的原生功能。
例如「整理目前可見的空氣品質讀值」可由畫面操作完成；「跨場域長期預測設備故障」需要資料與服務，這次沒有新增該後端。
官網登入不是 aiot／Odoo 主機登入的通用替代品。各 App 的真實帳號、主機與授權須分別確認。

## 5. 技術決策

- 同一 Gradle brand dimension 新增 `apporo`，保留 upstream 與 woowtech。
- 暫定 package `com.apporo.assistant`，版本 `0.1.37-apporo.1`；尚未註冊商店身分。
- 英文在第一次啟動設定一次；之後繁中或跟隨系統的選擇不能被重設。
- 品牌資源由同一生成器處理，手寫 Apporo 文案優先；namespace 與協定識別碼不改。
- 三款產品知識放共用知識庫：其他品牌也能操作已安裝的 Apporo App，這不改變助手身分。
- 不共用簽章金鑰。此分支產物是測試用；release 預設未簽章。
- 更新 API 預留 `WOOWTECH/apporo-assistant-releases`。目前尚未建立／發行，更新檢查可能顯示無法取得；不能說已是最新或公開可下載。

## 6. 驗收與剩餘工作

程式驗證：資源 XML、品牌字串／參數、知識格式、CLI Apporo 辨識、三品牌建置、既有測試回歸。
裝置驗證：英文首次啟動、繁中切換與重開、圖示／深淺色、共存安裝、模型、手機配對、瀏覽器、檔案、排程、通知、假商店同意／拒絕、CLI／MCP、助手解除安裝退出。
真實整合：Apporo aiot／platform／smart 各自安裝與登入後，以唯讀測試確認知識。帳號與目標主機尚待使用者提供或現場選擇。
不得在真實場域用自動測試任意控制門鎖、警報或營運設備。

發行前另需：最終名稱與 package、更新儲存庫、獨立簽章、新助手隱私說明、GPL 附件、版本更新測試與發布確認。
本分支不自動發布、不建立商店紀錄、不部署新服務。

## 7. 研究來源與可信度

- 目前程式碼與工具提示：能力存在的主要證據。
- `docs-woowtech/FORK.md`、既有 woow.3 測試報告：基底修復與限制；不能替代 Apporo 回歸。
- 本機 `woowtech-mika-research/03-woowtech-precedents.md`：aiot/platform/smart 維護前例。
- 既有 Apporo smart 品牌設定 `woowtech/brands/apporo.json`、官方 SVG：色彩、署名與圖形來源。
- `team/apporo-smart-1015/02-apporo-twin-pattern.md` 與 `05-brand-layer-plan.md`：歷史設計；商店狀態未在本次重新驗證。
- `apporo-docs`：場域與設備文件參考；不據此硬編碼裝置支援清單。
- 官網於本次查閱：產品定位參考，不視為手機整合已驗證的證據。
