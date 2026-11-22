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
