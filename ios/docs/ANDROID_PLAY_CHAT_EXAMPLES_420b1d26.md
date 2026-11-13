# Android Play-flavor chat copy audit

Reference: Android source commit `420b1d26f99110635d6a2827ee9414541c7a6c35`, `app/build.gradle.kts`, `app/src/main/java/com/wangzan101/mika/ui/ChatCopy.kt`, `ChatScreen.kt`, and the `app/src/woowtech/res/values*/strings_woowtech.xml` resources. The `woowtech` flavor declares application ID `io.woowtech.assistant`, version code 2 and version name `0.1.37-play.2`. These are source configuration facts, not verification of any particular uploaded or installed APK.

`ChatCopy.examples` chooses the six flavor-specific rows when `BuildConfig.FLAVOR == "woowtech"`. `EmptyState` is present when exchanges are empty and the conversation is not blocked. Each row replaces the input with its text; it does not send, attach a document, browse, or change memory. A previous draft is replaced. Source order and Traditional Chinese copy:

1. 幫我寫一則友善的訊息回覆
2. 幫我摘要附上的文件，列出重點
3. 在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較
4. 在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點
5. 記住我偏好使用繁體中文，回答簡短一點
6. 你記得我有哪些偏好？

At `ac1eae10828feede062bc00faa8120013d8d0678`, iOS exposed only row 3, also as a draft replacement. This candidate exposes all six. Their Traditional Chinese and English strings follow the Play-flavor source; iOS Simplified Chinese is a translation, not a Play-flavor string. The Android build explicitly excludes the generic `zh` resource configuration and declares English and Traditional Chinese resources. Neither the buttons nor this audit establish that the underlying document, browsing, or memory tasks work in all configurations. In this iOS candidate the existing document UI is PDF-specific, browsing and memory depend on their respective enabled/configured flows, and general attachments and combined attachment/tool flows remain separate work. No task is sent until the user invokes Send.

For Android's text composer, when the text is empty and voice conversion is not running, a non-null voice hold controller shows the mode-specific voice placeholder; otherwise `ChatCopy.placeholder` shows busy, answer, or idle copy. Idle uses `chat_placeholder_more` only if `ui.exchanges` is nonempty, otherwise the flavor's empty prompt. The voice hold controller is nil when voice is absent or explicitly off, not simply when permission is missing. On iOS `ac1eae`, the empty `TextField` shows `輸入訊息` / `输入消息` / `Type a message` when `session.entries` is empty and `繼續說點什麼…` / `继续说点什么…` / `Say something more…` otherwise. Its continuation Traditional Chinese and English match the Android source idle text-only strings; Simplified is an iOS translation. iOS does not implement Android's mode- or voice-specific placeholder behavior, and entries and Android exchanges are different state models.

Offline tests cover source copy and generated localization resources. The two added XCTest UI cases exercise draft replacement in all iOS languages and, separately, with a synthetic configured model. They require an iOS simulator and have not been run by the command-line-tools-only environment. They are not evidence of real service, APK, accessibility reader, or device behavior.
