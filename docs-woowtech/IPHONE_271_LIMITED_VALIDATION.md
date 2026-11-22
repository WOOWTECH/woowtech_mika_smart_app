# 原iPhone TestFlight271限定驗證（2026-11-22）

**271已原地安裝，選定穩定畫面未見回尾按鈕遮字；原始AX斷言失敗、過渡狀態及未測項均保留。尚非完整商用驗收。** 這批沒有發模型或MCP請求，不能填補原24輪的成功數。之後的連線探索／模型探測另開紀錄，不改寫本批零請求收據。

## 版本及證據

iPhone16,1／iOS26.5，`io.woowtech.assistant`／0.1.0(271)／TestFlight Beta Distribution。13:46:39及13:58:49兩份裝機紀錄一致，TestFlight顯示271「打開」。來源交接為 `28deae96ca3a7718743d78e6d0ddc2a42d1be020`，對應本機IPA SHA／UUID見[發佈紀錄](TESTFLIGHT_271_RELEASE.md)；沒有重新hash Apple重簽後的手機binary。

唯一原操作者沿既有無線配對一次恢復WDA（PID3290），未啟第二套服務或卸載主App。最終報告於14:05:22台北封存。父線與Mendel獨立核對已保存原始操作，沒有重做一次手機測試。

證據根目錄 `T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`；本批位於 `T/iphone-271-final-evidence/`。86次已授權唯讀GET均HTTP200、無截斷，取manifest及198項中的85項，總3,544,277 bytes（不含manifest）。逐項大小與SHA吻合，43項本地比較通過；未取全部vault或大活動log。

- 原報告 `report.md` SHA256：`cf44d222b8437961af911f42ce5bbd609a13b9dbe197f731e8d227bc812b8cb7`。
- `manifest.json` SHA256：`9eaf47e600408b5747536b285a88e13bb22ea7ff1a12c9d70bf82d92ae66f13a`。
- `independent-review.txt`、`independent-verification.private.json`、`verify-local-evidence.py`及GET回執保留比較方法、原失敗與限制；本地檔案0600，目錄0700，不將原訊息／記憶／認證內容放入repo。

## 有效結果及保留範圍

| 項目 | 實際結果 |
| --- | --- |
| 更新與原資料 | 原A31的18則role/index→顯示label hash、原兩筆記憶ID→顯示hash在前／後／最終比對一致。遠端vault bytecount／SHA紀錄一致；父線未下載解密完整vault。原PNG前／後副本實際下載，4270 bytes逐位元相同 |
| 中文及四行草稿 | 鍵盤開、關、再開後未送出文字保留；穩定尾端錯誤在記錄viewport內可讀，讀舊文及回最新可操作；最終草稿清空 |
| 回尾控制 | 獨立目視18／36／37穩定截圖，字形裁切在控制列上方，未見按鈕蓋住可見文字。部分原AX矩形斷言仍失敗，不能刪除或改寫成全PASS |
| 短對話 | 一個既有兩則正常回覆對話保留，做四行草稿／鍵盤操作後清空；不是兩／四則錯誤終態，也不是新模型正常回覆 |
| 附件 | 原圖縮圖→實際預覽→返回有操作紀錄，原圖hash不變；沒有把原圖保留當新相機／相簿功能通過 |
| PDF | 既有短中文來源實際產生、預覽及儲存，18708 bytes、1頁；cache與Files副本完全相同，獨立PDFKit抽取保留完整來源。SHA256 `14dc5328c1287e5a408ba3da04fdb0f7ed1f54dd19598ed157583f04db496593` |
| HTML | 同一來源實際產生、預覽及儲存，1271 bytes；cache與Files副本相同，內容與CSP存在。SHA256 `57c0b81dced0b4b0843ae43667cddd5123ac51b3b73beb88a130a2820c95f093` |
| 取消及CSV負向 | 分享面板取消正確，不稱送達；無表格時有原因且CSV產生按鈕停用。未做CSV正向、公式表格或接收端 |
| 清理 | 精確兩份cache＋兩份Files副本，刪前hash符合核驗副本，刪除成功、後驗OBJECT_NOT_FOUND；未清原資料。手機回A31、草稿空白、無送出中操作 |

原UserProfile來源及測試檔的前／後hash紀錄相同；獨立核對者未再次讀遠端原檔。A31及記憶比較是帶ID／索引的顯示hash，不是原記憶所有欄位或整份解密archive稽核。270記憶CRUD沒有重做，不當成271 CRUD PASS。

## 原始失敗與觀測限界

18號AX ScrollView矩形延至螢幕底，和截圖實際裁切線不符，原矩形與Return交集1598pt²、`return_below_AX_scrollview=false`；36號原矩形交2820pt²，但套當時viewport裁切後交0。保留原false／交集，不以矩形延伸直接判為可見遮字，也不宣稱全部AX斷言通過。這批沒有原AX XML可重新遍歷，subtree結果是當時helper與JSON紀錄。

拖曳後1.52998秒的觀測沒有Return，3.62620秒的觀測已有；兩者含AX查詢耗時，不能當精確render延遲或逐幀動畫沒有遮擋的證明。

短對話的兩個候選其實不同，最初錯配baseline的比較失敗仍保存。第二個正確baseline與實際after兩則hash相同；檔名含`short-error`不代表內容真是錯誤。沒有藉此掩蓋資料不符，也沒有把正常回覆冒充獨立錯誤案例。

## CPU窗口

三個窗口各8筆，App PID3300；下表保留DVT `cpuUsage`原讀值，不把它當連續曲線。

| 操作 | UTC窗口 | 筆數／最高cpuUsage | 最高physFootprint |
| --- | --- | --- | --- |
| 鍵盤 | 05:48:16–05:48:44，28.53秒 | 8／46.401436 | 54,346,888 bytes |
| 捲動／回尾 | 05:50:13–05:50:41，28.30秒 | 8／45.498864 | 55,297,184 bytes |
| 附件 | 05:52:35–05:53:04，29.12秒 | 8／42.853232 | 63,194,296 bytes |

另05:58:48 UTC有單筆cpuUsage0，早於之後的短對話與最終交接，不能說整個最後交接持續閒置。**本批未走原A31送出路徑，未證明高CPU根因已修。**

## 未測

獨立兩／四則錯誤終態、原A31送出→真MCP結果與來源、模型429恢復、多供應商／串流／逾時、>80頁、iPad／最大字級／降低透明度完整矩陣、多頁表格PDF、正向CSV、外部閱讀器／實際分享接收者仍未齊。原24輪維持實送2／正常0／未送22；後續新探測各自另計。[驗收缺口](ACCEPTANCE_GAPS_20261122.md)保留以上界線。
