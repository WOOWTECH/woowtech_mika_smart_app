# TestFlight 272 文件修補發佈（2026-11-22）

**0.1.0 (272) 已可供既有內部測試群組下載，且已在原iPhone原地安裝。** Apple於14:30:27台北查詢回傳 `VALID`、`IN_BETA_TESTING`、未過期；裝置於14:46:15回報272及TestFlight簽章，唯一操作者正在必要回歸。商用全數驗收尚未完成。

App `io.woowtech.assistant`／ASC `6834435121`，team `W4UWZ8NP2P`。沿用既有上傳、TestFlight及原iPhone實測授權；沒有新增測試者或送外部Beta審查。

## 來源及實作

正式封存來源 **`21a884b88434b88d148d91ab369acaa6fc435485`**，已推送 `origin/feature/documents-ios-android-20261120`。封存開始前工作樹乾淨，封存、Validate及Upload期間來源未變更。後續文件提交不改變272執行碼的來源。

- iOS／Android：來源解析或驗證失敗不再因修改輸出格式、選項或標題而消失；確實修改來源後重新驗證。可由標題修復的驗證條件保留修復路徑，格式相依writer錯誤不誤當永久來源錯誤。
- iOS：取消來源解析不把同一驗證物件變成不可重試；以attempt識別防止舊結果覆蓋新來源。
- 兩平台：64KiB CSV預覽截取完整UTF-8字元；只改預覽，不截短輸出文件。
- iOS：100MiB邏輯暫存額度與實際磁碟ENOSPC分開分類，24小時保留提示對齊既有政策。沒有擴大額度、保留期或分享授權。
- 包含271的回尾獨立列及鍵盤／多行草稿修補，見[271發佈](TESTFLIGHT_271_RELEASE.md)。未引入新套件。

## 必要回歸

| 執行 | 實際結果與限制 |
| --- | --- |
| iOS native289 | 40/40、failure0、skip0；24個core、13個export integration、3個UI，466.34秒、exit0、來源不變。Simulator實際執行，不是原iPhone商用驗收 |
| Android290 | 8/8、failure/error/skip0；DocumentExportSessionTest六案、DocumentCsvPreviewTextTest兩案，Apporo／WOOWTECH兩品牌Kotlin編譯通過，48.65秒、來源不變。沒有執行本修補的instrumentation或實體Android |
| 輕量必要檢查 | Python15/15、語系檢查及UI類別登錄通過；inventory144是登錄數，不是執行144個案例 |

native289保留一次PDF `Publishing changes from within view updates`及一次hosted viewport preference多次更新警告，沒有證明根因。後續診斷291／292各一UI案例通過但未取得目標堆疊；293僅attach預檢；294在PDF前找`chat.draft`的AX準備階段失敗並安全detach，未捕獲目標警告。這些不升格為警告已修，也不抹除294失敗。完整結果見[文件實作](DOCUMENT_GENERATION.md)。

## 封存及Apple證據

`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`；外層序列化heavy及來源收據在其父目錄。簽章／Apple原始日誌留在私密證據目錄。

- Release device archive及App Store匯出exit0，外層140.26秒；arm64、最低iOS17、10個Mach-O簽章核驗通過。`get-task-allow`關閉、DEBUG fixture未編入、ATS Debug例外不存在，privacy／用途宣告核對通過。
- IPA **8,150,699 bytes**，SHA256 **`ca91194cfd3a166973a76966585cfd01db3cd74d9a73fa2809d861324f317708`**。
- 本機匯出主程式SHA256 `cfa4ced2aafa2d29f1239f79f958ede2883076bb6ba4e5feab11b2be0535b342`；UUID **`9141F3D2-C65C-3FA0-A594-AC71DAB753B9`**，實際dSYM UUID吻合。Apple重簽／加密後下載包不主張逐位元相同。
- 14:17:24–14:19:00台北：Validate exit0，實際validation method marker核對通過。
- 14:19:58–14:21:49：Upload exit0，ContentDelivery確認 `UPLOAD SUCCEEDED`；buildUpload **`0e68081b-b002-4360-b2fe-551b16941c28`**。初始PROCESSING、errors／warnings空。
- 14:30:27：已登入Apple查詢HTTP200，272 `VALID`、`expired=false`、`usesNonExemptEncryption=false`。原「渥屋內部測試」group `69ca89bb-73ec-4e93-860f-35979a9601ff` 已關聯，internal `IN_BETA_TESTING`、autoNotify=true；external `READY_FOR_BETA_SUBMISSION`不是外部審查完成。

精確收據：`release-272/report.json`、`symbols-evidence.json`、`validation-272/receipt.json`／`safe-evidence.json`、`upload-272/receipt.json`、`web-status/272-processing-check.private.json`、`release-status-272.json`。保留封存report當時的未上傳旗標，後續以有時間的Apple查詢為準。

## 原iPhone交接及未驗收

沿用原分支作為唯一操作者，維持同一WDA及原資料。裝置metadata實際回報 `CFBundleVersion=272`、`CFBundleShortVersionString=0.1.0`、`SignerIdentity=TestFlight Beta Distribution`；14:46:42對應TestFlight版本列「打開」。14:47:03更新保留紀錄：conversations.vault 234173 bytes、learning.vault 20768 bytes、原PNG 4270 bytes，逐項bytes／SHA與本輪更新前備份一致。父線已用三次HTTP200唯讀取得上述小份回執，位於`T/iphone-272-install-evidence/`，不是僅轉述裝機成功。

原A31的18則前綴、原圖、兩筆記憶與UserProfile未提交檔保留。更新前採當下實際vault值作基準；271後續探測前後learning.vault的20789→20768 bytes差額已由外層JSON slash escaping325→304完全解釋，但未解密證明完整Learning state相同。詳見[271服務探測](IPHONE_271_SERVICE_PROBE.md)，不以先前UI批次hash相同覆蓋後續差異。

272文件及原A31兩個批次已執行並封存，[限定驗證](IPHONE_272_VALIDATION.md)保留實檔／CPU／清理及失敗。短HTML／PDF保存副本與cache相同，實際可見系統取消成功；無效來源、64KiB CSV及多頁長表等仍未測。

原A31實際只送一次已授權唯讀問題，約5.0207秒觀察到模型限流終態，沒有raw provider HTTP或MCP最終結果。17個CPU樣本最高52.5128%，終態後8筆中7筆0%，未重現持續100%，仍有15秒手勢client逾時。原18prefix保留，新增本次兩則合計20則，沒有直接修改vault或刪原對話。原24輪仍為實送2／正常0／未送22，後續獨立探測不混算。272淺深色／鍵盤及可恢復無障礙的限定外觀批次續做，未先宣告通過。

原A31高CPU根因、真Apporo兩筆tool_errors／unknown、模型／多供應商恢復、超時斷線、長表PDF／CSV接收端、Android同步視覺及其他[驗收缺口](ACCEPTANCE_GAPS_20261122.md)均未因此結案。
