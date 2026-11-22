# Android雙品牌APK：來源與簽章就緒，尚未裝機

**已從同一工作樹產出兩個標準Debug APK並核實內容；沒有執行新的Android儀器／實機測試。** 來源`57b9972f2df431f80aa7c25edc07e2981aff1389`，包含既有MCP不盲重送、安全診斷、結果警告及文件文案修補。先前62／92／40個精確測試仍各綁原提交，不加算成本輪測試。

| 品牌 | 套件／版本 | 產物 |
| --- | --- | --- |
| Apporo | `com.apporo.assistant`，0.1.37-apporo.9，code3809 | 101,796,020 bytes，SHA256 `56bb64e4838ae08ec4aff3217db2c88f22a1fb5d5b74590b4022f24fa5519180` |
| WOOWTECH | `io.woowtech.agent`，0.1.37-woow.8，code3808 | 101,790,378 bytes，SHA256 `f8fdfde2d2ded022b2e30281d2b9afd8afb1ef48852e5e94a0cf7cc65806fca2` |

SDK build-tools36的apksigner驗兩包成功，同一Debug certificate SHA256 `4fc27da651acdc5fab4d733095305b4c3d8b702a8ba16ab80934c9cc5b6edcad`。aapt2核package／版本／target35／debuggable及四ABI；生成的BuildConfig與實際APK DEX都含專案明定七位來源`57b9972`。初版驗證器錯用Git預設八位hash，修正後讀同包重核，未重建／重包來改來源標籤。

## 實際建置與保護條件

沿既有serial-validation→heavy.sh，鎖空閒時序列執行兩品牌assemble，僅暫停及恢復兩個已核准容器。第一輪8.33秒exit1，原因是本機未傳SDK路徑；原log／source／容器收據保留，沒有歸因產品或容量。第二輪補明確JDK17與ANDROID_HOME後**61.31秒exit0、source_changed=false**，最低可用2,401,161,216 bytes、未觸磁碟停止條件，兩容器恢復成功。沒有清除cache、修改全域Java或重跑已過單元測試。

私密產物在`T/resume-20261122/android-apk-readiness/`：兩份APK、`artifact-readiness.json`、公開環境與範圍收據、簽章／badging原始log。`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`；外層`R/android-apk-readiness-20261122[-02].*`保留兩次原始輸出。APK複本與build output逐SHA相同。

本輪ADB／裝置操作0。先前POCO曾發生前台被其他操作切換，尚未取得新獨占時段；不能假定現在空閒。裝機前仍需由單一操作者核實套件／現有公開簽章與資料保留，不能以Debug包覆蓋異簽章版本或卸載使用者資料。本包亦不是Play簽章版、效能包、UI驗收或商用接收端證據。

## 直接APK與Google Play分開

目前品牌Manifest明示直接APK管道。交付管道已提出選項；未有新選擇時沿既有管道，不在本輪擅自改成Play發佈設定。

若要提交一般Google Play新App或更新，現有target35不符公開門檻：官方自2026-08-31要求target36，延展期限為2026-11-01；既有App可見性是另一規則，永久組織內部私有App另有例外。這是依實際產物與[官方規則](https://developer.android.com/google/play/requirements/target-sdk)的推論，沒有真的送審或取得Play拒件。

團隊依[Android16目標行為](https://developer.android.com/about/versions/16/behavior-changes-16)核到WebTakeoverPage仍用legacy `onBackPressed`；正式target36遷移須接支援的返回callback並驗原有登入取消／暫放語意。Main Compose已有BackHandler與系統insets，沒有據此重寫全部UI。品牌的提醒權限／分發註解及可及性overlay另需依實際Play管道處理，不把本輪排除的手機控制／跨App能力重新納入。來源審查`T/resume-20261122/android-api36-parent-review/REVIEW.md`，不是已實作或Android16實測通過；正式遷移須遵循[官方測試流程](https://developer.android.com/about/versions/16/migration)。
