# 相簿取消：真機兩次讀取逾時，根因仍未確立

**原iPhone272相機入口／取消及恢復後檔案取消有限通過；相簿取消後立即讀回失敗保留。** 自然恢復及Simulator的後續通過不回填原失敗，也不代表原A31送出高CPU已修。

原iPhone16,1／iOS26.5，0.1.0(272)／TestFlight Beta Distribution，交接來源`21a884b88434b88d148d91ab369acaa6fc435485`。唯一既有WDA。全程0 Send／0模型／0業務工具／0快門／0選圖／0相機或相簿截圖，沒有App／WDA重啟、Home、安裝或權限重設。

## 原手機實際執行（台北時間）

| Case | 結果與限制 |
| --- | --- |
| 相機正式入口／取消 | UI限定PASS：18:53:20／46觀察拍照、閃光、1×及關閉控制，18:53:49回原QA、pending0／空draft、兩則hash相同。無權限提示或同意操作；未讀取預覽像素，不證實拍／影像品質或嚴格TCC值 |
| 相簿正式picker | 18:54:04觀察照片導覽、取消及disabled完成，0 asset選取／0全相簿權限操作 |
| 相簿取消立即讀回 | **FAIL保留**：18:54:22.740848取消意圖，23.202893 tap transport返回；接著source等headers **15.012061959秒**後socket_timeout。tap返回不證App即時畫面完成 |
| 後續狀態 | 18:55:09 WDA `/status` ready；`activeAppInfo`另等headers **15.012426958秒**後逾時。沒有server receive／handler／reply時間線，不能歸因USB或App主緒 |
| 自然恢復 | 18:56:05.976184 source成功，原QA兩則hash／空draft／pending0可讀；未重點取消／重啟。這是恢復PASS，不是立即取消PASS |
| 恢復後Files取消 | 18:56:19檔案picker可見，25.412679取消後仍pending0／空draft，限定PASS |
| 實拍／相簿自有asset匯入 | 未測。沒有可確認的自有拍攝目標，本批未按快門或選既有影像，不以UI控制代替正向媒體流程 |

## 時序及觀測界線

Parent從原始06／07 JSONL重算兩個15秒請求，均只有call_begin→open_begin→open_exception→call_exception，沒有headers／body／parse，沒有填造缺少的phase。正常tap另有完整七階段。現存WDA runner log僅1946 bytes且最後修改13:42，無本次逐請求server時間線；ready只證輕狀態可回，不證AX可用。

18:55:40–50的19筆App有效CPU最高1.142830%，晚於兩個逾時窗、早於首次確認恢復，不能拿來排除故障時高CPU。另19:02:57後同窗24行、剔首筆warmup後各PID23筆：App3358最高0.202748%、WDA3290最高1.030494%、Photos兩服務3453／882皆0%。Parent由原始多程序JSONL重算，這批明確在**恢復後**。

19:02:59–19:03:00取得一次selected stackshot，含App11／WDA6／Photos8及7條threads及image UUID／load地址，已完整取回61,136 bytes並核manifest。這是恢復後堆疊，尚不能定位原逾時／busy loop；沒有把原始地址當符號化根因。第一個診斷helper因Python3.9跨loop Event而0樣本失敗，修正後一次有限取樣，原失敗保留，不歸因App。CoreDevice lockstate讀取回錯，鎖定狀態unknown；未拿PasswordProtected或FaceID推論。

原A31全22則hash／空draft、兩記憶ID/display hash、兩個UserProfile hash收據與三個原檔bytes／SHA均前後相同。沒有新資產需刪除；QA附件父目錄及staging空、Inbox不存在。Parent核31項選定manifest entries、兩個原始時序、CPU及保留字典，見`parent-independent-verification.json`。最初capped JSON讀取未通過完整性guard，後依既有API的raw download取得完整stackshot並核SHA，未把截斷資料當分析完成。

私密證據根目錄 `T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`，本地 `T/resume-20261122/camera-photos-cancel272-20261122/`。report／result／manifest SHA256依序 `5070148bbaf50335311aaeca852bb58194062e6d328c158e431ca1f491298e97`、`91577dabf35449b43d34b43ab7322df2ab7a8da5b6faa6feb0712e2721f41d8d`、`65fde7de81d3534c8565067b7d0bbb1440f7f28593f70666d1efb5a6b34f5d07`。

## 新原生回歸304，與手機分開

新增`ChatAttachmentUITests.testSystemPhotoPickerCancelPreservesDraftAndAllowsFilePickerCancel`：獨立namespace與chat fixture、不發模型請求，但使用**真正系統Photos／Files picker**。保留非空未送草稿，取消後核相同value／可操作、無附件，且下一picker仍能開啟及取消，不選任何照片／檔案。

native304 **1/1、failure／skip／expected failure皆0**，case57.166秒、外層120.8秒、source_changed=false；heavy.sh序列化、兩containers恢復。取消tap到恢復觀察約2.372秒／2.312秒，各量測scope由console事件界定，非精確render延遲。末尾Simulator已shutdown的405清理訊息保留，不是測試失敗。

環境為Xcode27／iPhone17／iOS27 Simulator，runtime含`611d6bfa`，受測基底`b1fb2c25`加本提交測試檔；與原手機iOS26.5／runtime272同時有版本及環境差異，**沒有單變量排除或修復根因**。原始`R/native-304-photo-cancel.*`、`R/Documents-304-photo-cancel.xcresult`及`T/resume-20261122/native304-*.json`保留。此為測試覆蓋新增，沒有新增產品runtime修補或重建已上傳274。

接續原唯一操作者安排一次提前啟動觀測的受控重現，優先在失敗請求仍inflight時取樣；未取回封存報告前不宣稱重現／根因／修復。新版可安裝、真MCP及其他商用缺口依[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)。
