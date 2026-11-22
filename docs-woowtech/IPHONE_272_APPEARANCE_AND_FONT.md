# iPhone 272 外觀與字級還原：證據、修補及未驗項

272 實機確認空白輸入框在還原系統字級後保留異常高度。本次修補只在字級改變、草稿空白且未聚焦時重建 TextField。相同來源的原生版面回歸有一次失敗、一次加入暫時觀測後通過；不能宣稱間歇失敗或實機字級缺陷已完成驗收。273 的上傳與實機結果另列，不套用272結果。

證據根目錄沿用 `R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`、`T=R/testflight-20261122`。原 iPhone16,1／iOS26.5，TestFlight 0.1.0(272)，runtime來源 `21a884b88434b88d148d91ab369acaa6fc435485`。以下是既存實測與本次定位，獨立核對不另計成功輪數。

## 已確認的實機結果

- 已檢視淺／深色四行草稿、鍵盤及獨立Return列的代表靜態畫面；減少透明度、大字級與主題設定皆已恢復。尚未覆蓋所有字級／鍵盤／串流組合或動畫幀。
- 06淺色與11深色畫面均可見原4270-byte灰色手機外框圖形，部分受viewport裁切。先前「空白／漏畫」判斷過強；原始報告的false／INCONCLUSIVE保留，由 `T/iphone-272-appearance-evidence/independent-disposition.json` 校正解讀。圖片可見不等於文字閱讀或全部附件狀態通過。
- 字級受控循環：空TextField基準23pt、最大字級64pt；還原原設定後無導航／聚焦／輸入的26.441772、31.683505、41.520775秒樣本仍64pt。71.004240秒原生rect查詢在focus click之前，仍64pt。Focus與鍵盤顯示後23pt，收鍵盤及後續導航保持23pt，沒有輸入QA字元。這縮小至重新量測相關路徑，沒有證明UIKit內部cache因果。
- 原定0／5／15秒取樣未完成，首次source缺可見draft。08原始跨process時間計算有誤，原檔保留，只採ISO校正；離散樣本不當作連續71秒監測。
- 兩次swipe請求14.48401075／14.318277334秒均有回傳；另一GET/source為15秒客戶端逾時。後續ready／截圖成功與單點CPU0不能證明逾時全窗健康或歸因USB／App／WDA。

原20則display-hash、原18則prefix、原圖、兩筆記憶及遠端兩份UserProfile未提交檔均有分時核對收據；沒有下載或解密vault。appearance最終filemetadata早於最後導航畫面，不能延伸為該畫面後的整vault驗證；controlled批metadata涵蓋其循環。沒有為清理刪除原訊息／附件。

原始報告身份：appearance SHA256 `6cb3b977ec1fde57bca4b2650b448df7f30fc99a585e7d44cc2e38d5a6478e84`、manifest `b5a31e608a335c27290c4bba6cf39e212521d3e836af1dfca2d519683dea8ba4`；controlled報告 `bd7f6e758026a0db0537c4ab7bdb17aaa390e1c0c7e8608fc62a48ee4f125ab1`、manifest `0c8c84d0f62c2ef6a1e38d39b4c4ee60645e41b1c5c5a98941a4c40d2e28b92e`。完整核對與時序見T下 `iphone-272-appearance-evidence/`、`iphone-272-font-controlled-evidence/`、`appearance-font-handoff/`。

## 修補與原生回歸

`ContentView.swift` 的空閒TextField子節點新增穩定state ID；只有 `dynamicTypeSize` 改變且 `session.draft.isEmpty && !isEditingDraft` 才換ID。保留父ChatView、transcript、draft binding及focus；非空或正在編輯時跳過。沒有逐鍵更新ID、硬鎖高度、延遲刷新或重設捲動政策。空閒重建可能丟棄該原生空欄位的暫態undo/autofill狀態，須實機回歸。

測試來源為 `96317e5f` 加上述7行候選；ContentView SHA256 `2be5ad450cf8d9a0e181a6a86ae9bb1dde58fd93058bd98185f4a07d1d4197a8`。沒有改測試手勢、斷言、fixture或時間上限。

| 真實執行 | 結果與界線 |
| --- | --- |
| native301，`Documents-301-idle-font-refresh.xcresult` | 1 PASS／1 FAIL／skip0，source unchanged，外層218.43秒。最大字級Done83.941455秒通過；terminal版面59.226420秒失敗，首次portrait24pt拖曳後等不到Return，未進四行草稿。拖前與失敗終點error minY約331.333、draft23pt；位移斷言尚未執行，不能區分未捲動、回彈或曾被程式拉回。 |
| native302，`Documents-302-return-trace-font.xcresult` | 2 PASS／0 FAIL／skip0，source unchanged，外層327.85秒。最大字級Done87.822043秒、terminal版面153.476657秒；iPhone17／iOS27 arm64 Simulator。只加暫時DEBUG字級／拖曳觀測，原兩案及順序不變。 |

302有10個drag回呼、0個font onChange事件。首個24pt拖曳的bottom由238→249、viewport234，settle後follow=false，Return獨立列使viewport187；沒有在該觀測中被自動拉回。四行草稿使composer64→117、viewport234→181，settle請求後bottom238→185，完整錯誤及控制不遮擋斷言通過。這證明該次候選能完成原手勢，不是301根因修復，也沒有測到動態字級還原本身。

暫時觀測版本ContentView SHA256 `652fa74892f210e347b32633419be9690233e528aa9752d422a575134dd77e1d`；測後逐位元還原至上列候選hash。診斷patch、兩次原始結果、獨立301審查與 `302-diagnostic-disposition.json` 留於 `T/idle-composer-font-refresh-candidate/`。不把DEBUG觀測版本與最終Release稱為同一binary。

## 尚待驗證

新273必須核來源／簽章後在原iPhone原地更新，重驗空白未聚焦字級循環、非空／聚焦草稿保留、PDF預覽鍵盤警告修補、短歷史及四行Return。新字級程式與[鍵盤發布修補](KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md)都不在已裝272內。native301及295間歇失敗、WDA15秒延遲、原A31真MCP、模型限流、Android同步視覺及外部接收端仍未關閉，詳見[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)。
