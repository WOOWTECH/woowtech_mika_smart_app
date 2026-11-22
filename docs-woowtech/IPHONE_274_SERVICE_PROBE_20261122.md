# 274新鮮模型探測：UI限流，原A31服務回歸未執行

**2026-11-22 20:53這次實際探測仍失敗，正常回覆0；未再送原A31。** 這是新的真機結果，與17:21的272限流及[274零模型UI階段](IPHONE_274_CONTROLLED_UPDATE_20261122.md)分開。裝置為原iPhone16,1／iOS26.5，Development簽章Release0.1.0(274)，runtime`611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`；不是TestFlight實裝。

## 唯一請求與恢復

既有明確QA對話送一次20字、只要求2+3且不用工具／記憶的問題；沒有切換provider／model／權限或重試。20:53:16.606968送出意圖，20:53:20.070561首次UI觀察已接受，20:53:23.433234看見終態「請求太頻繁」。意圖至首次終態6.826294375秒是UI觀察界線，不是精確網路延遲或服務端接受時間；未取得原始HTTP碼，不能稱為已證實429。

沒有正常「5」，沒有觀察到工具活動／待確認，也沒有批准或操作業務工具。沒有服務端接收證據。依事先條件停止後續服務呼叫，不進原A31、不盲重送。終態後可收鍵盤、導航、查看記憶及返回A31，未重啟WDA。

同process monotonic CPU共13筆，排除首筆warmup後12有效，整窗最高39.989684325%、最大host間隔1.291697667秒。要求500ms不表示無縫覆蓋；這不是原A31的連續長串流或100%根因回歸。Parent從原JSONL重算peak／gap／UI延遲，並逐hash比較A31前後及QA原兩則前綴。

## 資料與清理界線

- 原A31全24／原22前綴、原4270byte PNG、兩筆記憶ID／顯示hash與兩UserProfile未提交檔保持。
- 既有QA原兩則完整，新一對提問／限流回覆留存精確hash。未確立單訊息刪除入口，故沒有為清理而刪掉整個原QA對話或raw改vault；本輪新增QA回合保留，不能稱全部測試資料已清除。
- 45個持久檔無新增／遺失，43檔bytes／SHA相同；conversation與Learning兩vault改變。前者與本次新增QA回合相符，後者未解密，完整plaintext是否相同未知；僅兩筆顯示記憶已核對。不能把前一零模型UI階段的45檔相同套到本輪。

## 證據及未關閉項

私密原件位於`T/resume-20261122/service-ready274-20261122/`，其中`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。report／result／manifest SHA256依序為`1c5d0984e7e0fa759808103697218f0b2fa15b0f5a93566ffa5a6fee0f8cedc6`、`809ff33de23932b886dc7f9de46f1b1e69cafe06d16df2024c2c6b6f956bec62`、`189df84a9224a897df3aa568ab850c8f72dafdfa4054e29750ffcab7b93a6304`。Parent實際取得／核19份選定原件與134項manifest，另有`parent-independent-verification.json`；不是新增19項實機通過。

原A31正常回覆／唯讀Apporo訂單MCP最終結果及來源鏈仍需App內可用模型，舊兩筆MCP錯誤也不能由本次限流解釋。已裝274安全分類日誌的真服務路徑尚待；UI限流不是MCP工具錯誤分類驗收。相簿取消、公開瀏覽與檔案等不依賴模型的可做工作另序列續做，不以本次失敗取代它們。
