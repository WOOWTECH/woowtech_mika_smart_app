# Chat 回尾控制與鍵盤版面驗證（2026-11-22）

**同一 runtime 的五個關鍵 native 案例分批通過：286為1/1、287為3/4、288針對287失敗案重驗1/1。287的AX逾時仍保留，未證明根因已修。尚未安裝271，也未完成原 iPhone 商用驗收。** 270實機失敗不因新 source 的 Simulator PASS 被改寫。

## 來源與證據身份

- Repo：`/Users/woowtech/Projects/assistant-documents-20261120`。本輪 source base **`16b4c54f9d4dff4d5983831dc2398f703515f5c2` + dirty working tree**；不能只以該 commit 代表受測程式。
- `R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；`T=R/testflight-20261122`。以下 `R/`、`T/` 均指此實際路徑。
- `R/native-286-return-trace-source-before.json` 與 `-source-after.json` 逐位元相同，也等於 `R/native-287-return-trace-source-before.json`；三者 SHA256 均為 `718ef848520d45a71c571393ef31e6280c5a9f8aee093b2fce8281a8942e0790`。獨立審查時十個已列 dirty 檔案全部吻合。
- Runtime：`ContentView.swift` SHA256 `81a14ad3723a1bdc4389ea4f9383b2e7eaaf34ee2d5986633f7cdc34f96967c7`；`ChatScrollFollowPolicy.swift` SHA256 `031a9e8118f556f9b12f5aa6d1e7bf87032c1fac6b346a3d70505144eb4471e8`。
- 286及更早關鍵證據的原始manifest保留於 `T/return-control-validation-evidence-manifest.json`；後續287／288與清理收據另見 `T/return-control-final-evidence.json`。兩者均記錄實際bytes／SHA256，不把舊manifest當成後續測試完成證據。

## 已證實的缺陷與最小修補

| 問題／可重查證據 | 本輪修補及保留的政策 |
| --- | --- |
| **270實機覆蓋文字**：iPhone16,1／iOS26.5、TestFlight 0.1.0(270)，來源鏈 `7026c468c4bb5ad2c51517d9611a93f1a4cce8e8`。4則訊息時，鍵盤開啟的錯誤框 `(14,301,299,44)` 與 Return `(219,319,150,35)` 重疊94×26pt；收起後重疊94×22pt。詳見 [iPhone QA24](IPHONE_270_QA24_FOLLOWUP.md) 與下列原圖。 | Return從 transcript overlay 改為獨立列；transcript與控制列置於 `VStack(spacing: 0)`，只有可見按鈕增加12pt上間隔。實際viewport扣除控制列，避免遮字或空控制仍預留間隔。保留 `ViewThatFits` 高度不足的fallback；>80則仍用既有頂端Latest，不新增重複浮鈕。 |
| **281已證實幾何誤分類**：`R/native-281-live-geometry.log` 11:20:47.011 focus=true；同revision4、height42822，47.509 bottom532／viewport528，47.518 bottom716／viewport528，follow true→false。`height-bottom` 減少184pt、距尾188pt，命中原「往舊文移動且離尾」判斷；此時是鍵盤佈局序列。 | 已知focus、keyboardDock或composer高度變化才呼叫 `beginLayoutTransition()`，進既有300ms安靜期並保留follow意圖。真drag、reader deceleration及既有held優先；layout中開始drag須以當下offset建立baseline。**不交換原reader／viewport判斷順序。此機制不是原A31持續高CPU的根因證明。** |
| **284 compact真失敗**：`R/native-284-return-trace-geometry.log` 11:51:04.795–05.261 viewport225→203→181，bottom維持238、following=true、無補尾。完整snapshot中error y331.3333435+h43.6666565=375，viewport底343，尾部實際超出32pt；並非浮點誤差或單純AX空樹。 | composer background的單一GeometryReader送出height；`PreferenceKey.reduce` 用 `max(value,nextValue())`，避免default0蓋掉正值。每輪重新reduce，縮小仍可觀測；只在有限正height且差值>0.5pt時進已知layout settle。原observe budget仍為每content revision最多3次，未用layout事件重設budget。 |
| **空白區拖曳觀測**：原生24pt觸控拖曳需確實進入drag政策，不能只看手指方向。283及286記錄實際文字位移14pt，才顯示Return並held。 | transcript加 `.contentShape(Rectangle())`，覆蓋空白gutter；保留simultaneous DragGesture及訊息長按。真正位移仍按原offset／settle判讀，no-op drag不能錯變閱讀。 |

270原圖位於 `T/iphone-qa24-images/06-round02-429.png`（SHA256 `442673c7772f6c319b921b038e033d4b9a09f9d6df47a4335b7b32fdf75af9bd`）及 `07-keyboard-dismissed.png`（`accf04fb24d0fda640f8911cf3b8fb6a255c610504a810343d31f50e1f2f2751`）；原檔來源、HTTP回執及AX座標見QA24文件。獨立審查已目視第一張及286下列兩張。

補尾請求在消費端再次檢查 `canScrollToTail = followsTail && !isDragging && !isSettling`，避免settle排隊後、新drag先發生仍被拉回。layout settle期間純串流growth不續期安靜timer；新content revision本身也不能越過settle強制捲動。

## 回歸結果與保留的失敗

| 證據 | 判定與限界 |
| --- | --- |
| `R/policy-283-layout-stream-growth.log`、同名`.json` | portable **3 tests PASS**；覆蓋281幾何、held、layout中真正drag的baseline與優先權、排隊請求消費前drag、連續純growth不飢餓、舊reader＋viewport保護及budget。這是policy程式檢查，不是實機觸控／VoiceOver驗收。 |
| `R/native-283-summary.json`、`R/native-283-return-trace.log` | 80邊界案PASS、terminal案FAIL。terminal原先多個AX查詢在10秒predicate內耗時，早期frames有效、後續emptytree，再於teardown恢復完整；未證明產品crash、記憶體問題或waiter interruption的確切因果。 |
| `R/native-284-summary.json`、`R/native-284-attachments/D6B6AA6E-B747-47FC-8A7D-960B9C07B1EE.txt` | terminal FAIL；普通portrait各階段PASS，compact四行未送出草稿時尾端實際被裁切。保留此產品失敗，不以285或AX解釋覆蓋。 |
| `R/native-285-summary.json`、`R/native-285-return-trace.log` | terminal FAIL：`portrait-returned`後 `focusDraft` 的exists查詢 t68.03→77.28（9.25秒）後失敗／emptytree；**未進compact，不能算compact重現**。initial COMPOSER=0僅為該次觀測，不能單憑此推斷所有後續尺寸。 |
| `R/native-286-summary.json`、`R/native-286-return-trace.json`、`.log` | **1/1 PASS，test112.314秒，外層207.91秒，exit0，source unchanged**。iPhone17／iOS27.0（24A434）arm64 **Simulator**，WoowAssistant；`Documents-286-return-trace.xcresult`。完整selector與command如下。 |
| `R/native-287-summary.json`、同名wrapper／log | **3 PASS／1 FAIL、skip0**：attachment117.130秒、NoOpDrag161.231秒、Returning178.592秒通過；80邊界123.138秒失敗。外層661.51秒exit1，source unchanged。送出後message80的AX讀取逾時；失敗截圖及後續完整AX證明81則／新訊息已存在，但本次沒有完成取消及返回原對話，不算該案通過。 |
| `R/native-288-summary.json`、`R/native-288-return-trace.json` | 僅重驗80邊界，**1/1 PASS、skip0，100.656秒**；外層178.07秒exit0，source unchanged。81則送出→82則取消且停止文字完整可見→分頁切換→原1998則保留皆通過。 |

286已執行命令（證據用途，非重跑指示）：

```text
python3 /Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/native-observed.py 286-return-trace WoowAssistantUITests/ChatReturnToLatestUITests/testTerminalErrorRemainsReadableWithReturnControlAndCompactKeyboard
```

286的 `R/native-286-return-trace-geometry.log` 11:59:14.194–14.657顯示composer64→73→95→117、viewport234→225→203→181；14.969 settle=true／needs=true，14.979 request canScroll=true，14.981 bottom238→185。AX error底322位於viewport底343內；先前136.3203125→64也證實max不會鎖住歷史最高值。隨後真拖曳使follow=false，收鍵盤仍held，明確Return後恢復follow。

- `R/native-286-attachments/2FC111F3-D495-40AF-B92C-E6B78978AB83.txt`：完整階段、single-snapshot幾何及所有assert結果。
- `R/native-286-attachments/DF252352-CF09-408F-BB7A-5D772D87535E.png`：compact鍵盤開啟，完整terminal文字可見。
- `R/native-286-attachments/8D6460A5-05A7-429E-A15D-652417F2E8BA.png`：真拖曳held，Return在viewport下方獨立列。閱讀狀態允許尾文離開viewport；此圖不主張所有錯誤文字仍完整可見。

287各案最終結果（均在`WoowAssistantUITests/`）；只有失敗案另以288重驗：

| Selector | 結果／秒數 |
| --- | --- |
| `ChatReturnToLatestUITests/testEightyMessageBranchSwitchesToPagedTranscriptOnAcceptedSend` | 287 FAIL／123.138秒；288 PASS／100.656秒，兩筆分開保留 |
| `ChatStreamingUITests/testReturningToBottomByDragOrButtonResumesLaterFragments` | PASS／178.592秒 |
| `ChatStreamingUITests/testNoOpDragAtBottomStillFollowsLaterGrowth` | PASS／161.231秒 |
| `ChatAttachmentUITests/testSixEntryTranscriptAcceptsFourthTurnWithKeyboardAttachmentsAndMemory` | PASS／117.130秒 |

287記錄80案出現AX讀取失敗：PID39860的04:04:17.964 CPU54.5%／RSS約424MB、04:04:27.616 CPU0.4%／RSS約410MB、04:05:01.653 CPU0.1%／RSS約188MB；最後兩筆之間約34秒沒有ps樣本，不能稱為連續低CPU，也不能據此歸因memory或disk。該次short draft高度維持64，沒有證據把失敗歸因於max reducer。

重驗前僅清理本案可再生Android／device編譯中間檔，兩份201MiB合成檔改存gzip並逐位元雜湊還原驗證；所有xcresult、IPA／archive、來源與手機資料保留。清理收據 `T/owned-intermediates-cleanup.json`，外層 `R/cleanup-288-owned-caches.json`；不是磁碟或記憶體根因證明。288仍用相同程式、資料生成、斷言與時間上限，未重送或跳過。

## 審查與驗收界線

獨立source review未發現此次runtime／test最終diff的具體blocking finding。Return列只改實際剩餘viewport；layout／drag origin分離、held不自動恢復、queue消費再檢查及純growth不續期均保留。沒有新增frame clamp、恢復scroll或放寬cancel完整contains；80頁尾只針對已觀測的 `2.0345047232694924e-05pt` 誤差使用一個physical pixel容差，仍要求可見交集≥44pt與完整precision紀錄。

terminal幾何改用單次 `app.snapshot()` 本地遍歷；完整可見、Return與viewport／composer不相交、控制位置等條件保留，hittable／enabled在幾何通過後直接assert。attachment送出維持一次tap，鍵盤退出及兩次穩定frame共用原10秒ready budget；訊息接受及完成共用原15秒reply budget，未以重送或重新啟動掩蓋失敗。這些改善不能宣告AX空樹問題已根治。

DEBUG COMPOSER／LAYOUT／SETTLE／REQUEST／FOCUS與既有TRACE暫留，均受 `#if DEBUG` 及 `-UITestTranscriptDiagnostics` 限制，Release不包含此診斷分支。source review沒有另行build或重跑測試。

上述native案例使用UUID隔離資料、DEBUG合成模型／錯誤／長歷史fixture，驗的是實際ChatSession、存檔、分支、keyboard、gesture與rendering路徑；**不是非fixture商用驗收**，不證明真模型成功、原A31高CPU根因已修或MCP收到／完成請求。既有270實機模型限流、真MCP及文件等缺口仍依 [驗收矩陣](ACCEPTANCE_GAPS_20261122.md) 和 [270發佈證據](TESTFLIGHT_270_RELEASE.md) 追蹤。

**VoiceOver未實測**：新layout settle在VoiceOver執行時不啟用，沿用原保守reader政策；不得寫成VO通過。硬體鍵盤、其他螢幕／字級及新271實機仍未由這批案例覆蓋。新版本須原地更新保留資料，實機重驗270曾遮字的短歷史、收放鍵盤及錯誤終態。發佈狀態另以有時間的TestFlight收據為準。

## 長按選取補充回歸295／296：保留間歇失敗

為檢查contentShape／回尾手勢未攔截原生文字選取，在runtime來源`21a884b8`補跑既有`ChatStreamingUITests/testSmallScrollAndLongPressDoNotJumpWhenLaterChunkArrives`，不是重做前述五案湊數。

- **native295：0/1、failure1、skip0，201.299秒。** 小幅捲動與原生長按選取選單已出現；65秒等待SCROLL_SECOND_END逾時，helper line453失敗。原45秒第二段／25秒結束fixture時序及斷言未改。xcresult／錄影／末端AX持續為第一段的證據保留，尚無CPU或producer callback時間線可歸因。
- **native296：1/1、failure0、skip0，217.883秒。** 僅加暫時DEBUG fixture產生／consumer預覽更新前後NSLog及外部1Hz own-Simulator觀測；沒有產品修補、改fixture delay／斷言／等待。14:57:15.369第二段yield前後、.373→.378 consumer assignment前後均可見；原選取、更新後選取及閱讀位置斷言通過。測試在第二段驗完後teardown，未等producer_finish是原流程，不能列為producer缺失。

296共144個ps樣本，長按後40個樣本最高67.1%，未達連續8筆>90%的一次profile觸發條件，**沒有取得sample堆疊**。整輪最高151.6%在長按前；Simulator多核心CPU估計及RSS不當iPhone實測。兩輪各自source_changed=false，296與295之間確實有上述DEBUG觀測差異，不主張完全同一binary；一次通過不能否定295。

外部`T/native-295-selection-evidence/`保留tests／summary、42份debug附件、原錄影及119／125／161／185秒畫面、暫時patch及`295-296-disposition.json`；`R/native-296-selection-trace-geometry.log`及process.jsonl／summary保留控制事件及時間線。暫時patch先逐位元核對僅含本輪兩檔診斷，再reverse-check／reverse，兩runtime檔回到21a原hash，未留下新Release程式碼。兩輪heavy序列化，已授權兩容器均恢復。

**295根因未定位，未修復，沒有安排相同條件反覆重跑。** 兩輪不代表原A31送出故障或非fixture串流已驗收。271實機穩定畫面／AX限制另見[限定驗證](IPHONE_271_LIMITED_VALIDATION.md)，272原機回歸另收實際結果。
