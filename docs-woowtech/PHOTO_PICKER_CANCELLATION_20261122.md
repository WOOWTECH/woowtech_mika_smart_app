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

上述批次沒有故障窗內的多程序觀測，後續一次受控重現另記下節。新版可安裝、真MCP及其他商用缺口依[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)。

## 19:17受控重現：已取得故障窗CPU，沒有可用故障堆疊

同原手機／272／空draft及已知QA兩則，再走正式Photos→不選asset→Cancel一次。0 Send／模型／MCP／截圖／重啟。19:17:28.614573–29.144866取消tap返回；其後唯一source call於19:17:29.147076–44.199757逾時。Parent從原始HTTP重算wrapped call **15.052504292秒**，open→exception **15.042794916秒**，仍無headers／body／parse；不是server handler耗時。

CPU與HTTP同一host process／monotonic。50行、首行warmup排除後49有效，原失敗請求窗各程序30筆：App3358最高**19.562875%**、WDA3290 **72.277508%**、Photos3453 **29.037690%**、Photos882 **0%**。觀測25.010260秒，≤30秒；實際最大host接收間隔**1.271978292秒**，不把設定0.5秒當連續無縫可見，也不能排除樣本間峰值。整段窗的較高App／Photos峰值含開picker前置，不混成故障窗數字。

source等待open約2.079870秒仍inflight時，觸發一次stack；起訖均在失敗請求內（call後2.080203–3.500245秒），但留下**TypeError、無可用stack檔**。舊helper把取得、cleanup、projection及encode包在同一catch，沒有保存stage／traceback，無法證明取得本身失敗或UUID是唯一原因。純記憶體檢查只證原生UUID有序列化風險；沒有補抓事後stack或再送取消來填造。

19:18:40一次有界恢復讀回成功，原QA兩則／空draft／pending0；19:19原A31完整22、兩memory、UserProfile收據及三原檔metadata均前後相同。沒有新資產須清理。Parent取得20項manifest原件，重算時間／CPU／保留字典；報告`T/resume-20261122/photos-cancel272-inflight-20261122/parent-independent-verification.json`。report／result／manifest SHA256依序 `7123b136b92a258b5f867927498610db999fe7a5eade87941c6bec50124c0e1b`、`5f1327f4bf1075f33fca276b3cd889fa4cd0f09d31659bc6e545eff14eac288e`、`5f31906ccb55813081f8b26107adbbb9aee5b69dd856e68db8aa2d71272674e8`。

團隊獨立重算並以22項純記憶體檢查指出：應分stage保留已取得資料、使用UUID-only encoder、驗schema與必要App/WDA threads、保留不含例外內容的frame資訊、先encode再原子寫入、對完整capture lifecycle設界線。候選修補再有86項離線檢查，尚未部署／手機驗證；這些不是新增商用測試通過數。優先完成[274受控更新](IPHONE_274_CONTROLLED_UPDATE_20261122.md)；若新版本仍發生，再用已審候選進行一次有界故障窗取證，不重播舊case充數。

目前只確立可重現的AX source header等待逾時，**仍無USB／App／XCTest的可檢驗根因結論，沒有據此修改產品程式**，原A31送出100%問題亦另列未關閉。

## 274單次正常對照，與272失敗分開

原iPhone／iOS26.5已受控原地安裝Development簽章Release274，runtime`611d6bfa`，非TestFlight，詳[安裝及UI證據](IPHONE_274_CONTROLLED_UPDATE_20261122.md)。21:01:45.042752取消意圖、46.977949原生tap返回、48.715836 source觀察完成。相同正式picker未選asset，實際Cancel HTTP一次、其後source一次，**本次沒有重現15秒逾時**。原要求15秒timeout不變。

source snapshot範圍1.736081167秒；Parent另由原HTTP JSONL算call_begin→call_return為1.734829542秒，兩者界線不同。2.08秒檢查時source已完成，故stack擷取0；沒有補抓事後堆疊。新observer候選的實際capture／cleanup分支仍未驗證，不能由這次正常對照或86項offline檢查宣稱修復舊TypeError或逾時。

同process CPU觀測7.028325625秒，9行／排warmup後各程序8有效；App3629峰18.098640%、WDA3290峰11.055939%、Photos兩服務30.471315%／0%，最大host間隔1.076315334秒。Parent重算原始CPU peak／gap及唯一兩個HTTP請求，這不是失敗窗CPU或原A31送出回歸。

準備失敗另留：第一次picker過渡尚無Cancel；後續caller手動UI intent與transport helper的同名O_EXCL檔在HTTP前衝突，原experiment JSONL為0 bytes。修正transport收據名並用新attempt子目錄後只送一次實際Cancel，未覆寫舊檔／重開picker或服務。修正前只重現本機檔案衝突、未完整fake-transport排練；Parent訊息到達時真請求已完成，故未為補排練再跑手機。不能把未傳輸的intent當實際取消次數。

返回QA四則hash相同、空draft／pending0；A31全24／原22前綴、原圖4270 bytes、兩memory／兩UserProfile源檔保留。相對上一[模型探測收尾](IPHONE_274_SERVICE_PROBE_20261122.md)，三原檔及兩vault差異metadata相同、無新檔／遺失；不把安裝前45檔完全一致套到已經新增QA回合的狀態。本輪0Send／模型／MCP／相簿截圖／asset匯入，沒有新資產需清理。

原件`T/resume-20261122/photos-cancel274-inflight-20261122/`，report／result／manifest SHA依序`801ea1c98fc1ca8aabf9bdede94144f99a402bacf8a946d50912f9b5ff3934bb`、`d38e5514d44fef011780ea436fbee92f4375f1144ab49ceeb47691a80435c5f8`、`1c5240f24276a9c3e7700a7503044b3758b8b55008333706f6a48e9503a0b268`。Parent核154項manifest中的20份實際原件，另有`parent-independent-verification.json`。單次正常不關閉舊兩次Photos逾時、274 Settings返回逾時或原A31 CPU根因，亦不算實拍／選圖正向驗收。
