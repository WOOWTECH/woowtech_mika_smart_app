# 原iPhone272附件：大檔拒收及PDF恢復

**201MiB拒收、小PDF匯入／系統三頁預覽、取消／移除及限定清理已有真機證據；待送卡片直接預覽未提供。** 不屬App產生多頁PDF或模型／MCP驗收。

2026-11-22台北18:30–18:48，原iPhone16,1／iOS26.5、0.1.0(272)／TestFlight Beta Distribution，來源`21a884b88434b88d148d91ab369acaa6fc435485`。唯一既有WDA，0 Send／0模型／0業務工具／0新對話；以原已知安全QA兩則對話的未送草稿操作，不改A31。

| 真機case | 結果及界線 |
| --- | --- |
| 正式picker選取201MiB文字檔 | PASS：實寫210,763,776 bytes，AFC完整讀回hash相同；App顯示單檔200 MB限制，pending0，附件目錄／staging／Inbox未留該copy。未測精確200MiB邊界 |
| 三頁繁中PDF之系統Quick Look | PASS_WITH_LIMITATION：45,068 bytes，來源PDFKit3頁／逐頁文字核對；手機三頁不同標題及頁碼可觀察。初始原生頁碼徽章曾遮部分首頁標題，原限制保留；Parent親看settled首頁及第三頁文字可讀，不宣稱全部過渡無遮擋 |
| 正式匯入及copy完整性 | PASS：pending1，讀回實際App copy 45,068 bytes，SHA256 `a5b3d6d025dcfebf8afe7404101e30dff958df3a9d4f88c0c2efb5340883daa2`，與來源完全一致 |
| 點擊待送PDF卡片 | FAIL_FEATURE_GAP：一次真點擊仍留chat／pending1。iOS `ChatAttachmentTray.content`沒有onOpen，僅已送附件提供預覽；不將picker的Quick Look冒充App待送卡片預覽 |
| 再開picker後取消 | PASS：pending仍1、空draft、QA兩則hash及copy不變 |
| 正式移除及清理 | PASS：pending0，item UUID目錄／copy消失；三個獨有Documents輸入逐檔完整讀回核hash後刪除，來源子目錄不存在，staging空／Inbox不存在。既有QA附件父空目錄保留，未手動刪除 |
| 81-byte備用文字匯入 | NOT_RUN：只準備／讀回／清理，因PDF恢復成功而未匯入，不增加通過數 |

前後A31全22則display-hash、空draft、兩筆memory ID／顯示hash、原4270-byte PNG及兩個UserProfile hash收據一致。兩vault與原圖bytes／SHA在本批前後相同；沒有解密vault、變更字級／模型設定或刪原對話。這個相同界線不能移植至先前新增訊息的送出批次。

保留自動化失敗：drawer邊界guard、一次拖曳未帶出目標、不支援的scroll路由HTTP404及Quick Look控制name／label差異。後以可見控件及正確frame繼續，沒有改15秒timeout或另開WDA。原始過渡source／截圖非原子；拒收／匯入以後續真終態判斷。未觀察crash／凍結，但**本批沒有CPU量測**，不算效能根因驗證。

## 與Android及後續範圍

Parent來源比較確認Android `ChatAttachments.kt:PendingTray`亦只有移除按鈕、待送卡片沒有onOpen，已送附件才可開啟。因此直接預覽是兩平台共同產品優化缺口，沒有把它誤報成iOS獨有退化或悄悄改原產品。原操作者的FAIL_FEATURE_GAP原報告保留；未因兩平台相同就改成PASS。

與文件匯出editor相反，Android匯出來源可編輯，iOS是唯讀snapshot；這是另一個已確認差異，不靠注入假assistant資料補CSV／長報告測試。本批自有PDF是正常附件輸入，不能證明App文件產生器能處理長表跨頁。相機實拍／照片匯入、送出附件、接收App、空間不足等仍另驗。

## 取證

私密原始根目錄 `T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`，本地 `T/resume-20261122/attachments272-large-recovery-20261122/`。Parent取回主報告／manifest與選定原始JSON、4張安全PNG及實際App copy PDF，共30項manifest entry逐檔bytes／SHA吻合；另核22prefix、memory／UserProfile字典、三個保護檔metadata及精確清理，見`parent-independent-verification.json`。未下載201MiB輸入或vault，未執行下載helper。

report／result／manifest SHA256依序 `fa6d081cb43a18092ae3ce8539047658abbddff59e1d84f07f0611892c1d6752`、`0a5a8c36492c75297dbb5358e48bb34bae6aabe590789d5c4602999e216941b6`、`4819a399d564703a114d474c9f078267bda1de62b88ddc86f01723b55c935d5d`。完整商用未驗項仍列[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)。
