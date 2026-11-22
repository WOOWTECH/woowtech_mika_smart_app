# TestFlight 273：鍵盤發布與空輸入框字級修補

**0.1.0(273) 已通過 Xcode Validation 並上傳 Apple，尚未證實處理完成、可安裝或273實機驗收。** 原iPhone目前最後已核版本仍為272。上傳不代表商用驗收，App Store公開送審未執行。

## 來源與實際產物

| 項目 | 已核結果 |
| --- | --- |
| App／Team | `io.woowtech.assistant`，App Store Connect `6834435121`，`W4UWZ8NP2P` |
| 版本／來源 | `0.1.0(273)`；`4e2c8c643505f4306f2cc2cb4d1f5b644c2fd287`，clean tree建置 |
| 修補 | `96317e5f` 移除鍵盤duration-only發布；`4e2c8c64` 字級改變時只重建空白／未聚焦TextField，保留父view與草稿binding |
| IPA | 8,154,242 bytes；SHA256 `7184be05c47cf5ea768a25004e49e9ee288fae6eecc0174ee7328be54abd02a4` |
| UUID | archive App、export App及dSYM一致：`27A2CA71-4CFA-3C14-9AD6-C87988EEB51D` |
| Release驗證 | iphoneos、minimum17.0；10個Mach-O及codesign、profile／entitlement、隱私manifest、非DEBUG等既有release gate通過 |

`R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；`T=R/testflight-20261122`。真正本次產物位於 `T/release-273-final/`。較早 `T/release-273/` 是963來源的另一份本機包，未上傳，不能混用。

## 執行及核對

| 階段 | 真實結果 |
| --- | --- |
| archive／signed export | `R/release-273-final-archive.json` exit0，139.35秒，source_changed=false |
| Xcode Validation | `T/validation-273-final/receipt.json` exit0；外層93.82秒；archive distribution task=validate、validationEvent.state=success／Validation succeeded |
| Upload | `T/upload-273-final/receipt.json` exit0；外層97.55秒；2026-11-22T08:44:55Z完成，task=distribute、uploadedBuildNumber=273、uploadEvent.state=success／Uploaded to Apple |

三階段均透過既有heavy序列化；原授權兩個測試容器均恢復。沒有重跑正常CI，也沒有將空間門檻當阻礙。

已補上實際archive輸入的完整manifest gate，包含App、dSYMs、root Info.plist、symlink與mode；不是只核對未作上傳輸入的IPA。原始完整payload SHA256 `8322ac373c80779652de5ef9b95db2b20129a9d420c6d56eb32943d431367671`。Validation僅在root Info.plist增加Distributions；移除該key可精確重建原937 bytes／SHA，其他163個entries不變。保留原seal，另封存新完整manifest SHA256 `e76a02e8a31b3b0e99a6576552c1ff97ef5ce90a55ec3b695ecf5e9baf3bd2f7`，Upload前逐項重新核對。Upload後亦只有root Info.plist改寫發佈紀錄，App及dSYM payload未變。

獨立審查發現並關閉上述B1來源gate缺口，收據 `T/keyboard-font-release-review/B1-closure-readonly-receipt.json`；原始審查與補充結論皆保留。實際helper版本hash記於Upload receipt；Validation使用的前一版helper另封存，沒有把不同階段說成同一腳本版本。

## 測試與未通過項

[鍵盤發布修補](KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md) 的299為真publisher紅燈、300三案通過；[字級及外觀證據](IPHONE_272_APPEARANCE_AND_FONT.md) 保留301一過一失敗，以及302只加暫時觀測後兩案通過。302實際手勢、錯誤可讀及四行草稿斷言通過，但沒有觸發動態字級變化；觀測patch已精確撤回，不能當273實機字級修復證據。301拖曳、295串流的間歇失敗仍未證根因。

原iPhone唯一操作者已收到帶來源／UUID的273原地更新及限定回歸指令（T/iphone-273-handoff/，HTTP202）。尚須核TestFlight可見／實裝、資料保留、空白未聚焦字級循環、四行／鍵盤／Return與PDF預覽。既有模型限流與缺少QA表格／長文來源不以mock補驗收；原A31真MCP、Android同步與接收端等仍依[缺口矩陣](ACCEPTANCE_GAPS_20261122.md)。

## 原iPhone可見性與被動時序：16:55封存

2026-11-22 **16:50:47+08:00**，原操作者由既有TestFlight版本入口檢查一次，只見272／271／270；沒有273、install tap或循環刷新。Parent已親看 `T/iphone-273-availability-evidence/06-TestFlight-build-list.png`，SHA256 `d4f1be89b0d993196f020f156275a8a4c77f7becfa0d6c85626096e96398c6cc`。16:51:08重新核手機仍0.1.0(272)／TestFlight簽章；273的字級、PDF、模型及MCP測試未執行。此為該手機／帳號的可見性，不足以判斷Apple processing、compliance或內測群組原因。

原A31的20則／18prefix、圖片、兩筆記憶、設定與兩個UserProfile保護檔均有前後收據，parent另核20則display-hash及跨批baseline一致、保護檔收據一致；未下載／解密vault。回App第一次source缺draft的AssertionError保留，後續恢復不證其根因。

後續既定收尾程序首次實際附掛先前已審的被動計時：helper與ui.py hash吻合，未改原15秒／idle／request，無額外裝置請求，finally撤回原call／OPENER binding，logging failure0。Parent逐行重算147事件／21次呼叫，每次均有7個有序階段；最長call1,572.493708ms、open到headers1,571.107209ms。首個自然source控制事件964.843208ms，有headers／read／parse／complete。這批沒有15秒症狀，也沒有CPU或server receive／handler／reply時序，不能據此歸因USB／主執行緒；首次缺draft在附掛前，不能將後來正常trace移作其診斷。

273可見性report／result／manifest SHA256依序為 `961e1ff622957a9dcd8c75a8414b48e9f4a2401cb89f6bde6d1ddda8e2b279bd`、`3d765368d89dd5bb68936ec7a6bb606ef9a7faec1547eb728033b4f6e47acf20`、`cdd4fec72e38d11df9dec91ea0be1325810d9de98b0abbc91cfb7f148f538ecb`。Parent取得兩批共6份主報告與20份選定證據，全部HTTP200、bytes／SHA吻合；上述重算見同目錄 `independent-verification.json`，不是重新操作手機。

另外，272限定盤點6個明確QA對話／12個可用assistant觀察，最長182字、單行、無表格標記，沒有匯出。96是觀測到的不同UI row hash數，不是完整archive稽核；業務尾段排除，原始未封存page3 snapshot被後續resume取代的界線亦保留。CSV／長篇PDF正向因此仍未測，報告及manifest位於 `T/iphone-272-csv-readiness/evidence/`，不可用這次盤點冒充CSV產檔。

Apple官方管理分頁登入已過期，既有帳號登入流程目前需要擁有者在官方頁輸入密碼／必要2FA；不讀取、猜測或要求聊天提供憑證。另一次官方altool唯讀build-status因缺明示認證回error30，不能以此當processing失敗。Xcode既有distribution登入已完成真Validation／Upload，兩種登入狀態分開記錄。等待管理頁恢復期間，另安排**272**現有同provider一次有界可用性確認，結果須獨立綁272，不回填273。

## 17:57後續可見性檢查

上傳完成逾一小時後，唯一原操作者正常進入版本群組一次，**17:57:56+08:00仍只見272／271／270**，沒有273；未刷新、未安裝或重簽。Parent另親看 `T/resume-20261122/testflight273-visibility-recheck-20261122/06-build-list.png`，SHA256 `3321e0c4051a700ed3a3eda14df687060120c50576d1afa1db9057aaa1f6ad88`。17:58:32裝機仍272／TestFlight簽章；273來源與UUID未在手機驗證，字級／鍵盤／PDF回歸仍未測。

此時A31為22則，源自[17:21原A31失敗終態](IPHONE_272_VALIDATION.md)；本輪前後22項hash一致、空草稿，原兩vault、PNG及UserProfile收據一致。沒有模型／MCP新請求。四個自然程序的20次WDA呼叫／140事件留存，不額外產生探測請求；本批沒有重現15秒逾時，仍不能證USB／App根因。

本輪report／result／manifest SHA256依序為 `2b52adf6e1271dc65cfd8729aad407a6d611e50358be5a797ce96f34c01ce891`、`94a892221b7938465f9c816f32169885017d9a8bb0cce678c84da233b8bdd6df`、`7886c035d0bda1b369d0c0092b09576d5823a669e9f65e398105bded569abb5a`。Parent取回主報告、選定原始JSON／PNG／timing並核manifest；詳細範圍與重算見同目錄的Parent收據。Apple處理／合規／群組／帳號哪一階段尚未有官方證據，不猜原因、不重上傳同一包；官方管理頁登入仍待擁有者完成。
