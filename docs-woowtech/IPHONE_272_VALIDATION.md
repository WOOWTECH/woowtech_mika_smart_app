# 原iPhone272文件及原A31送出限定驗證（2026-11-22）

**272已裝機；短HTML／PDF交付限定通過，原A31一次送出仍以模型限流失敗。** 這次未重現持續近100% CPU，仍有原生手勢15秒逾時，沒有真MCP訂單結果。完整商用驗收未完成，後續外觀批次另收結果。

版本0.1.0(272)、io.woowtech.assistant、TestFlight Beta Distribution，iPhone16,1／iOS26.5；發布交接來源`21a884b88434b88d148d91ab369acaa6fc435485`。[發佈鏈](TESTFLIGHT_272_RELEASE.md)保留本機IPA／UUID與Apple回執，未重新hash Apple重簽手機binary。唯一原操作者沿同一WDA實測，父線／Mendel只讀核對其證據，不另開裝置服務。

`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。以下兩個批次及原QA24、271模型探測各自計數，不能互換。

## 文件批次：零新模型送出

遠端`testflight272-documents-20261122-1437`於15:06:05台北封存；本地`T/iphone-272-documents-evidence/`。實際來源為原A31第7則assistant的39字既有回覆，無表格；hash與原18則前綴及已取回舊來源一致，未注入假助理訊息。

| 項目 | 有效結果 |
| --- | --- |
| HTML | 實際產生、預覽／關閉重開、系統保存；saved與cache逐byte相同，1271 bytes，SHA256 `2510bd7803d8ba6d74cd64d00f961e7bc9bdfe3d69ff13a86994c56ed5680264` |
| PDF | 同樣實際生成／預覽／重開／保存；saved與cache相同，18442 bytes，SHA256 `e6e38a6e19f2459a4e6af788468feec77ac37a6837944259b2bf6cd28688d603`。本機PDFKit獨立抽取1頁，完整39字來源恰出現一次 |
| 安全內容 | HTML獨立解析UTF-8／來源／CSP；default、script、connect、img、font、media、object、frame、base、form均none，style僅unsafe-inline；沒有script／iframe／form／事件或外部資源屬性 |
| 失效及草稿 | 格式切換、重開editor不沿用舊結果；四行56字未送QA草稿hash保留後清空。無表CSV停用Generate，只是負向guard，未生成CSV |
| 系統匯出取消 | 先前兩個看似「verified」收據其實仍等待目的地，不能算成功。15:01:52點擊實際可見／啟用的取消Button內座標，15:01:56 App顯示「已取消操作」、editor返回，才列限定PASS |
| 保留 | 四份A31完整18則role/index/hash字典相等；兩筆memory ID／顯示hash直接相等。更新前、更新後首次啟動前、文件後的兩vault及原圖metadata大小／SHA相同，僅限此批取樣點 |
| 清理 | 精確2個saved＋2個cache，刪前hash_checked、deleted、absent_after皆true；只刪本輪QA文件，本地證據副本保留 |

保留失敗：14:50:17原生swipe發生15秒client socket.timeout；2.177秒後單筆CPU0%，其後source讀取1.122秒可用，不是連續profile或根因證明。系統檔案取消曾誤選AXvisible=false的Other；未成功的紀錄與不支援native predicate400收據均保存，不將後來成功取消回填到原失敗。

Mendel獨立取得60個filesystem GET均200、無截斷，共91257 bytes，59/96個manifest項＋manifest；58項本地比較通過。沒有下載vault、讀key或執行下載helper。報告SHA256 `2ff37cfb8491ec154ba95d643881bc8f14a6fecae5bb437170615be133ad7416`；manifest `eeffe634fac0005d6f33f16f28c1c377172a11532c9952807ee1514662e285f3`。UserProfile保護僅核前後hash紀錄，未獨立重讀遠端源檔。

**文件批未測**：無效來源／取消重解、64KiB UTF-8預覽邊界、正向CSV／公式／試算表、長表／多頁PDF、生成中取消、quota／ENOSPC／24h、實際分享接收者。native28940/40與Android2908/8不移植為上述實機PASS。

## 原A31單次送出：正常回答0

另立遠端`A31-send272-20261122-1506`，15:12:06封存；本地`T/iphone-272-A31-send-evidence/`。先備份，核原第16則36字明確唯讀訂單問題的hash，再在同一原對話輸入並送出一次；沒有換新對話、擴大業務範圍或重送。

- 15:08:34.014送出意圖，34.907 native tap返回；35.984首次觀察user已接受，39.034首次觀察錯誤終態。意圖→終態AX觀察約5.0207秒，**不是精確上游延遲**。
- 終態「呼叫模型失敗：請求太頻繁，請稍後再試」，正常回答0。沒有raw provider HTTP，不能獨立斷言HTTP429／帳號額度根因。
- 17個DVT離散CPU樣本涵蓋07:08:05.301–07:09:11.249 UTC，最高52.5128%，physFootprint最高76023160 bytes。終態後8筆中7筆0%，另收鍵盤附近42.9313%。未觀察持續100%卡死，沒有連續profile可排除瞬間尖峰或證明正常模型串流已修。
- 收鍵盤成功；讀舊文native swipe又發生15秒client逾時，未重複同手勢。其後source1.1655秒可讀且已捲到訊息6–12，稍後單筆CPU0%；原圖Quick Look重開／關閉、記憶唯讀導航及返回A31可操作。

安全dispatch收集嘗試覆蓋15:08:02–15:09:09，stdout／stderr為0 bytes，沒有可見控制事件證明logger交付，**不能由空log推服務端零請求**。兩次UI觀察未見工具指示，MCP counter為null；沒有訂單最終結果／資料來源，原tool_errors／unknown尚未驗證修復。

原18則prefix逐ID／role／index顯示hash與文件批封存基準一致，最終20則為原18＋本次user／錯誤終態。新增兩則保留，草稿清空；沒有刪原對話或直接改vault。實際下載的原PNG前／後副本4270 bytes完全相同；兩筆memory ID／顯示hash仍相同。整份Learning檔SHA不同、20768→20772 bytes；操作者安全counts記錄slash escaping304→308，其他外層長度相同，只解釋+4 bytes，不證plaintext或save原因。父線未下載此vault解密。

父線獨立取回32個GET均200，31/41項manifest檔＋manifest；所選42841 bytes逐項大小／SHA吻合，prefix、prompt hash、17CPU樣本、兩memory字典及PNG實檔重新比對通過。`independent-verification.json`保留方法及限制，下載helper只讀不執行。報告SHA256 `59b534457075548a0c5781834aafbd29c11c90c9d1a2de34eed09c0a4c95b4e8`；manifest `b88a890a713d5ae4412d6ca20303fd87a79cdf9c568e792bdd5159bee21976be`。

**原A31根因仍未關閉。** 此輪只觀察中文輸入→送出→限流終態及後續互動；成功模型／正常串流／真MCP全鏈、原MCP錯誤及20–30輪正常對話未完成。原QA24正常成功數仍為0，不能把本次已接受或錯誤終態計為正常完成。

## 既有供應商唯讀盤點

15:14:13另封存`providers272-readonly-20261122-1512`，本地`T/iphone-272-provider-inventory/`。既有列表為非lazy VStack／ForEach，AX有一列provider且新增footer可見；總數1，目前被主模型選用。只記本次index／名稱hash／主模型列hash，前後選擇相同；無登入、測試、刷新、增刪、切換、模型或MCP動作，最後返回原20則A31空草稿。

「非帳號API類型」僅依272 providerLine固定文案的來源映射推論；列表未直接提供更細來源型別或憑證設定，strict credential布林保留null。**清單「已連線」是固定文字，不能當有效金鑰或服務可用性。** source審查亦確認keyStatus在metadata查詢失敗時可能fallback已儲存；本次沒有為此讀secret、匯出providers.json或完整設定AX／截圖。

本機`T/multi-provider-readiness-path/`另有實際來源路徑／副作用審查：App使用全域roles.main、無per-conversation override；部分picker會隱含發固定probe、切換會持久化consent／revision。這是只讀來源分析，未切換實機或新增診斷入口。只有一個既有供應商，沒有可直接使用的既有替代項；不將單一模型限流推成全供應商故障。完成真服務驗收仍需App內可用的模型／已授權替代帳號，憑證不貼入報告。
