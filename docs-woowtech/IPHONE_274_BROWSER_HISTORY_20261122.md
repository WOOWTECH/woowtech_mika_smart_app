# 274公開頁面歷史：一次正常重啟保存通過

原iPhone16,1／iOS26.5，Development簽章Release0.1.0(274)，來源`611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`。**本次公開URL載入及歷史重啟保存限定通過**；不等於舊native自訂搜尋案例或全部網站流程通過。模型／MCP／Send均0。

正式介面只開一次含自有QA fragment的example.org公開URL。21:05:54觀察真正WebKit標題／說明及可用reload、無stop／loading／browser.error／workspace.error，留實際頁面截圖；沒有只憑addressPill匹配就結案。Release無DEBUG ready元素，沒有聲稱量到內部didFinish時刻。頁面關閉後21:06:22確認新history ID／穩定文字hash，以及原一筆history仍在；產品保存URL會移除fragment，不將fragment假裝成持久識別。

全任務idle且原A31空draft／pending0後，一次正常terminate／launch App。重啟先顯示空白新對話，原驗證腳本錯誤假設會自動回A31而停下；保留這筆斷言，使用正式drawer選回原對話，不再重啟。21:07:13新history同ID及文字、原history與搜尋引擎hash讀回，無workspace error，未再點history觸發第二次導航。這驗的是公開URL，不是登入、跨源跳轉、下載或自訂搜尋引擎查詢。

原A31全24／原22前綴、原圖、兩記憶及兩個UserProfile未提交源檔保留。Conversation／Learning／PNG三原檔與[Photos階段](PHOTO_PICKER_CANCELLATION_20261122.md)metadata相同；瀏覽庫及另兩個Library檔的變更另留收據，45檔無新增／遺失，沒有宣稱所有檔仍相同。頁面已關閉，**一筆QA history保留**：正式UI無單筆刪除入口，沒有清空全部或raw改庫來湊清理完成。

私密原件為`T/resume-20261122/browser-history274-20261122/`，`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。report／result／manifest SHA256依序`1a767a6db1a4257c6a14a19693a64be41ec2311034b7f9ffe2c1602e2b04f736`、`67e854a9536c6d38095c28dbb4057da19ff320000a6ab6b5876bcafc88fea68f`、`c04f5181124946cf9f1e9144f491977b1fbe13aca027a54cbf2ba4f7161cda95`。Parent取16份選定原件核bytes／SHA與176項manifest；重算來源／歷史字典另留私密收據。相同產物的獨立核對不加算新實機案例。

沒有新增產品runtime修補或重觸正常CI。舊失敗與[native297前置修正](BROWSER_HISTORY_PERSISTENCE_VALIDATION_20261122.md)仍綁原版本；原A31正常MCP、逾時根因及完整商用矩陣繼續開放。
