# 渥屋助理 Google Play 版本（開發中）

這是 `playstore/woowtech-compliant-20261111` 分支的商店版原始碼。**尚未提交 Google Play 審核，也不是可公開發布的商店版本。** [完整研究與驗收狀態](../docs-woowtech/PLAY_STORE_RESEARCH_2026-11-11.md)。

商店版套件名稱為 `io.woowtech.assistant`，可與 [main 分支的 GitHub APK 版](https://github.com/WOOWTECH/woowtech_mika_smart_app/tree/main) 共存。兩個 App 的本機資料不會自動共用。

預定功能：使用者自備模型帳號或 API Key 的 AI 對話、語音輸入、內建瀏覽器、記憶，以及遠端對話。商店版不提供跨 App 自動操作、無障礙服務、遠端喚醒／解鎖、ADB 手機助手、背景定時操控或 App 內 APK 自我更新。目前有手機在線時的唯讀對話與附件存取；離線同步尚未完成。AI 回覆檢舉的正式收件端、資料安全揭露及實機驗收仍待完成。

渥屋科技維護此專案，基於 [Mika](https://github.com/wangzan101/Mika)（Apache-2.0）；與 Mika 原作者沒有隸屬或背書關係。[授權](../LICENSE) · [第三方聲明](../licenses/THIRD_PARTY_NOTICES.md) · [問題回報](https://github.com/WOOWTECH/woowtech_mika_smart_app/issues)

## English

This branch develops the Google Play edition of woowtech agent. It has **not been submitted to Google Play** and is not ready for public store release. Its package ID, `io.woowtech.assistant`, can coexist with the [direct APK edition on main](https://github.com/WOOWTECH/woowtech_mika_smart_app/tree/main); local data is separate.

The intended scope is AI chat with a user supplied model account or API key, voice input, an in-app browser, memory, and remote chat. Cross-app automation, AccessibilityService, remote wake/unlock, ADB phone control, scheduled phone tasks, and in-app APK self-updates are excluded. Online read-only conversation and attachment access is implemented; offline sync remains open. The AI report production receiver, data disclosures, and device acceptance testing remain open. See the [research and status report](../docs-woowtech/PLAY_STORE_RESEARCH_2026-11-11.md).

Maintained by WOOW TECH CO., LTD. and based on [Mika](https://github.com/wangzan101/Mika) (Apache-2.0). This project is not affiliated with or endorsed by the Mika author.
