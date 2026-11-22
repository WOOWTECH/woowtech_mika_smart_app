# 274 Settings返回對照：兩次正常，一次前置未確認

原iPhone16,1／iOS26.5、Development簽章Release274，runtime`611d6bfa`。**尚未定位或修復間歇15秒source讀取逾時。** 以下與[限定UI](IPHONE_274_CONTROLLED_UPDATE_20261122.md)／[最大字級捲動](IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md)的兩次FAIL分開，不以後續正常結果覆寫失敗，也沒有取得新的實機故障stack。

| 獨立執行 | 真結果 |
| --- | --- |
| 不改設定控制，21:24 | 既有QA4、空draft／pending0。Settings只開不改；App activate1.500511750秒，唯一source HTTP2.015805375秒完成，2.08秒判斷已結束，stack0。CPU9行／8有效，整窗App峰18.08582348%、最大gap0.941722041秒。source窗各程序只有2筆，App峰0.001497975%，不能排除間隙峰值 |
| 原字級還原擷取準備，21:32 | max1／100%後，activate返回約0.19秒，立即source0.602830583秒／HTTP200，但安全selector沒有QA4／draft。嚴格guard停止，未到最後還原擷取；CPU0／stack0。只有過渡收據，沒有全畫面，不能說App真空白／卡死或稱NO_REPRO；還原後等3秒，QA4／空draft正常 |
| 修正準備後單次循環，21:38–39 | activate後實等3.141740333秒，仍須QA4全hash／draft／pending0才繼續；max64pt實際確認。還原0／50%後，唯一最後activate1.632587750秒、source HTTP1.666735417秒，field23pt，QA4完整。2.082703083秒判斷已完成，stack0；CPU9行／8有效，整窗App峰28.41323103%、gap1.272449791秒，source窗各2筆App峰0.002018005% |

前置修正是針對已看到的轉場race：加入可量測準備時間後仍核正確畫面，**沒有延長原15秒HTTP timeout或用固定等待代替predicate**。未確認的原實驗保持STOPPED；後一單次實際循環才有NO_TIMEOUT_REPRO結果。沒有重做既過的7次字級捲動、PDF／Photos或模型；實際控制結束後不再循環找failure。

兩個有觀測的正常控制都在App activate前開始同host process CPU，≤30秒；原source Future未取消／替換，候選observer只在pending條件成立才可擷取。本輪兩次均未達條件，沒有事後補stack或符號化。App PID重新核為3681，沒有沿用重啟前3629；WDA仍3290。沒有故障窗CPU、server handler時間線或可用新stack可判USB／App／XCTest原因。

每個新caller在動手機前都有禁止網路的fake transport分支演練，核收據命名、超時、停止及準備guard；合成stack與圖片放offline目錄，**不算實機／商用驗收**。實機原件放phone目錄。原observer SHA `dbbbc8950a3cc5cf909a20ec87a730aad8c8e3d6312a5439d957645c379df519`未改，實際capture／cleanup仍未驗。

三批均0Send／模型／MCP／asset；原A31全24／原22前綴、原PNG4270 bytes、兩記憶及兩UserProfile未提交源檔保留。最後QA4／A31空draft、pending0，字級原0／50%、reduce0、無App／WDA重啟，原三檔及45檔差異metadata與前輪相同。完整45檔比對仍由原Mac操作者執行，未傳私密index／備份；Parent獨立核選定收據、實際訊息map、原CPU及HTTP事件。

## 證據

根目錄`T/resume-20261122/`，`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。

| 子目錄 | report／result／manifest SHA256 |
| --- | --- |
| `settings-return274-control-20261122` | `4d9a8cd4eb9b3fcc94272d1093053c7c654a9a297aefa16f3e2bf275cbb103e3`／`6ff7560782d833beb923782a6995bb494547104fa0d7656e8016dbc02bd0ea2e`／`ea908d3447c11cbe234afcca52a1d421ce9166add4d27ac09323110e751f4c1b` |
| `controlled-font-return274-20261122` | `f91ed326c7110270a3702b43d7cf36f57975cf76c360cda5e8f06e9050029a42`／`3e6bc65033c8e885469085bb9e31fadeb2b0dcf566495ef4b68091f99fbf4281`／`518a9c0a8a02a13d162106807bd386e748ee6523d2660e7de4508f4165e2430a` |
| `controlled-font-return274-settle3-20261122` | `37e3099f7204001dc8dd4be893cbffdc629e2dfd8b2ab1f1c6c8845151ec3309`／`646bfff910f6b3b6a627edff3a47b5a97c343bf0e152d282791f6e9f7c76ab79`／`42b5179905176765eccb8a0743646c910e73b51e517b9ebce01396cdcf8269f0` |

Parent各取正常兩批10份manifest原件並重算CPU／HTTP，留`parent-independent-verification.json`；第三批manifest使用entries而不是files，按實際schema解析，沒有把offline的假stack當phone檔。本輪新增的是正常對照及觀測準備修正；原A31高CPU／真MCP最終回覆仍開放，模型最新證據仍是[20:53限流](IPHONE_274_SERVICE_PROBE_20261122.md)，沒有新增服務請求。
