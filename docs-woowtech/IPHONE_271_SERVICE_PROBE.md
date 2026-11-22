# 原iPhone271服務探測與記憶封裝差額（2026-11-22）

**單次新模型探測失敗；MCP當下已載入41個工具，不等於業務工具完成。** 這批與先前[271 UI限定驗證](IPHONE_271_LIMITED_VALIDATION.md)分開；原QA24維持實送2／正常0／未送22。

來源`28deae96ca3a7718743d78e6d0ddc2a42d1be020`，0.1.0(271)，iPhone16,1／iOS26.5。沿既有TestFlight裝機metadata及同PID3300交接，未重新hash Apple加密binary。證據根目錄`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。

## 一次模型可用性探測

14:26:27.230台北單次send意圖→14:26:28.760首次觀察QA user已接受→14:26:32.825首次非sending錯誤終態：「呼叫模型失敗：請求太頻繁，請稍後再試」。UI send1、accepted1、正常0、retry0。5.595秒是意圖至AX終態觀察差，非服務端精確延遲。**本輪沒有raw provider HTTP response，不能獨立寫成HTTP429已證。**

四個稀疏CPU樣本跨度12.215秒；最高13.4728%在send意圖前，三個送出後樣本最高0.7396%。不是連續profile，不能排除間隔尖峰或證明原A31送出卡死已修。三次AX poll及一次後續確認未見MCP／技能／記憶／瀏覽工具UI指示，沒有backend audit可保證實際工具零次。

精確QA ID及marker一路對齊至刪除確認、archive後驗：僅QA會話移除，原A31仍18則、空草稿、非sending；摘要記原role/index顯示hash相符，本批沒有逐則字典可重新計算。兩筆記憶的ID／顯示hash字典可直接比對相同；原PNG metadata大小／SHA前後相同。本批未下載原圖或整份archive，也未重算遠端UserProfile原檔，只核對既存前後hash收據。

獨立取回`T/model-ready-271-evidence/`：31個filesystem GET均200、未截斷，30/32項manifest檔及manifest本身共30040 bytes。42個本地一致性檢查通過是證據核對，**不是模型PASS**。報告SHA256 `fd5f560e0241a86325dcea4dacd1816d687a119c10858470c0d13c0e79696d5b`；manifest SHA256 `7c428e4d2b0ae0566d17ff465ea480ad9b5d674099ce37bbbb37aa2d8d03ed1e`。下載helper未執行。

## MCP觸控路徑限定證據

14:31:50起當下Apporo顯示connected、協定2025-03-26、41工具，Connect停用。這是App當下已載入目錄，不是新的ping或工具結果，也不回填為之前兩次手動Connect成功。

既有helper實際取AX整列矩形中心做座標tap。新唯讀局部截圖顯示停用膠囊位於整列左側，中心在膠囊外白底；原生StaticText descendants為0、hitPoint查詢WDA HTTP500。這支持先前可能未命中，**不是啟用按鈕hit-test證明，WDA500也不是MCP HTTP錯誤**。本輪沒有第三次Connect／模型／業務工具呼叫。ChatSession在模型前可自動取得MCP catalog，提供中間QA送出可能觸發discovery的路徑，缺網路時間線不能確認因果。

`T/mcp-hitpath-271-evidence/`四次GET200，報告／result／安全局部PNG與manifest逐項SHA／大小一致，父線已實際查看PNG。報告SHA256 `8e6921e4da9afbf024c57b9b7d7d092f525de0940b7f8c9f64caa46075bd9f2d`。團隊的Connect安全診斷候選留在外部，未套主樹、未包含於272，不當根因修補。

## learning.vault少21 bytes

舊封存20789 bytes與探測後20768 bytes的SHA確實不同。取得272更新前已存在的備份後，其SHA精確符合271探測後metadata；只在記憶體中解析AES-GCM封裝外層，未解密、未讀key或保存密文。

| 外層計數 | 舊份 | 新份 |
| --- | --- | --- |
| raw bytes | 20789 | 20768 |
| base64字元 | 20392 | 20392 |
| decoded sealed bytes | 15293 | 15293 |
| 不含slash escaping的外層bytes | 20464 | 20464 |
| escaped slash數 | 325 | 304 |

20789=20464+325；20768=20464+304，−21 bytes完全由外層JSON slash escaping差額解釋。**等長密文與編碼尺寸相符，不證明plaintext相同、完整Learning state未變或哪個save觸發。** 原兩筆記憶顯示一致仍僅為部分資料保留證據。

`T/learning-envelope-probe-followup/`保留12個GET回執、來源／備份鏈、counts-only腳本及11項計數檢查；新舊完整vault未保存至本Mac。原報告的差異及先前缺新備份的判定均保留，未回寫成全庫相同。原A31送出、真正訂單MCP結果／來源、兩筆tool_errors／unknown、模型記憶語意及多供應商恢復仍未驗收。
