# iPhone 270 手動記憶 CRUD 證據（2026-11-22）

**270 手動新增、同 ID 修改、關鍵字持久化及限定刪除：限定 PASS。** 這是原 iPhone 已完成操作的原始證據與獨立核對，父線沒有重複操作手機；不代表模型記憶工具、技能語意或全案驗收。[24 輪追蹤](IPHONE_270_QA24_FOLLOWUP.md)仍為實送 2、正常完成 **0**、未送 22，本次不增加成功對話輪次。

裝置為 iPhone16,1／iOS26.5，安裝紀錄為 TestFlight 0.1.0(270)。來源鏈沿用[270 發佈交接](TESTFLIGHT_270_RELEASE.md) `7026c468c4bb5ad2c51517d9611a93f1a4cce8e8`；本輪沒有重新 hash archive binary，不能把交接來源寫成重新核對二進位。這不是 271 通過證據。

## 操作與資料保留

| 核對項目 | 結果與界線 |
| --- | --- |
| 新增／修改 | 記憶數量 2→3；編輯器讀回的合成內容與關鍵字逐字符合建立規格。修改後仍為同一 ID、總數仍 3；內容與關鍵字均確實變更，不只核報告的 PASS 布林 |
| 兩次真重啟 | 修改後 PID **3143→3237**；刪除後 **3237→3238**。兩次 terminate 回傳 true、終止後 app state=1；intent／progress／final 與後續讀回順序一致 |
| 重啟讀回／清理 | 第一次重啟後仍 3 筆，實際編輯器內容／關鍵字逐字符合修改版；限定刪除本次新增項目後 2 筆，第二次重啟仍 2 筆且測試項目不存在 |
| 原記憶保留 | 建立前與清理後的兩筆原記憶 ID→顯示 label SHA256 map 相同。未公開原 ID／內容；這不是整份 vault bytes 或原記憶所有欄位的比對 |
| 原對話保留 | 重啟後最初停在預設空白對話，`original-chat-after.json` 的 **0 則／空 map 比較失敗保留**。之後明確從抽屜選回 A31，`original-chat-restored.json` 的 **18 則 role/index→顯示 label hash** 才與之前逐項相同；不宣稱自動恢復原畫面，也不把第一次失敗當成資料遺失 |
| 原圖／受保護檔 | 原圖前後記錄均為 4270 bytes 且 SHA256 相同；兩份受保護來源／測試檔的前後 digest 紀錄相同。獨立核對沒有再次讀取手機原圖或遠端原檔；最後畫面為 A31、空草稿、無 active submission |

修改後編輯器截圖可見合成內容，但關鍵字顯示有省略號；完整關鍵字持久化的證據來自記錄的 editor AX value。原對話核對亦是 AX label hashes，不是完整 archive bytes。

## 取回回執與完整性

外部證據根目錄 T：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。以下檔案均位於 **`T/memory-270-evidence/`**，只列可核驗索引，不將原始記憶、ID、認證資料或私密檔案放入 repo。

原始報告來自遠端 `iphone-qa/memory-crud270-20261122-1133/report.md`。獨立取回僅使用指定 session filesystem GET：**39 次 HTTP 200、無 truncated**，取得 manifest 與其列出的 **38 個選定檔案**（含 3 張截圖）。38 檔的 bytes／SHA256 均符合 manifest，合計 **664781 bytes**，不含 manifest；不是下載全部未知附件。文字按 utf-8、圖片按 base64 解碼後核 hash；本地證據檔 0600、目錄 0700。

| 外部相對路徑 | SHA256 |
| --- | --- |
| `report.md` | `69fa0352f013a480a4ea8dea1f05817902b1e3f805a5f6947a2fe8f091127ec1` |
| `result.json` | `049d950c5a23f05c4f78f6fdabac7c7de8946871813892f139699aff7a20f756` |
| `source-provenance.json` | `8de53a0571c7836ffb455242bf6ef0ae7a11fb99d6b98a64971ffd4a854c0496` |
| `manifest.json` | `e4ccbd4bfff17b4bd160502ab390277a5ddfe8f113da038e832fb7ea46773735` |
| `http-receipts.private.jsonl` | `f0c71689ebe75b5f2bf1021d531d157ce578cda5ae4215f1b2f488aa03b91ff1` |
| `report-http-receipt.private.json` | `977914c12baaa2083bb525ee6cc3cd483e2082457f4c7af75d2cd6b6ebf40c85` |
| `independent-verification.private.json` | `fc40f6567718115d5e2c4588e9c1762d2f0a71e568a31dd65f695854bfd2f2e8` |
| `downloaded-SHA256SUMS.txt` | `055002749fc032d9b617d67e014fffdb8910e64ded0e28349c80b622f800c5a6` |

HTTP 回執保存 GET 路徑、時間、HTTP 狀態、回應與解碼後 hash／bytes，沒有認證 request headers。`result.json` 的報告 hash 與實取 `report.md` 一致；獨立比較結果亦核實來源、重啟、清理及原資料保留。原工具活動快照不是完整紀錄，不以它證明所有其他操作均不存在。

## 尚未涵蓋

本輪遠端報告模型／MCP請求均為 0；獨立核對者只取回證據，未操控手機、啟動 WDA 或送模型。**270 模型記憶工具／語意反轉、技能生命週期與中文語意檢索仍未測**，MCP 真服務結果、其他供應商及 UI 修補另依[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)追蹤。手動 CRUD PASS 不替代這些驗收，也不更改原 24 輪的正常完成數。
