# Chat attachments — parity with the Android pro edition (woow.10)

Owner decisions (2026-11-12, main conversation, AskUserQuestion answers):
- 19:16 "iOS 在本機讀內容，Android 列待修": iOS reads attachment content on the device; the Android
  store build 0.1.37-play.2, whose main task has no sandbox (`read_file` missing), is listed as an Android bug.
- 19:19 the reference is the GitHub pro edition io.woowtech.agent 0.1.37-woow.10 (tag v0.1.37-woow.10 = b3a5fe0d),
  which "supports all kinds of attachments".
- 20:17 "拿掉，完全照 Android": the iOS-only chat PDF form (page range, password, three approvals, evidence
  cards) is removed. PDFs are ordinary files.

## Behavior (Android source: app/src/main/java/com/wangzan101/mika/ui/ChatAttachments.kt, AttachSources.kt, AttachmentMessage.kt)

- "+" (`chat.attach.toggle`, "新增附件" / "收起附件面板", turns into × in 0.2 s) opens an inline panel under the
  input bar in the keyboard's place. × brings the keyboard back; focusing the draft or sending closes the panel.
- Panel (`chat.attach.panel`): three tiles 相機 / 相簿 / 檔案 (76 pt, 16 pt corners), then 最近的照片.
  - 相機: `UIImagePickerController` (iOS needs NSCameraUsageDescription; Android uses the system camera intent).
  - 相簿: `PHPickerViewController`, images, up to the room left in the tray; no permission needed.
  - 檔案: `UIDocumentPickerViewController` for any type, several at once, copied into the app.
  - 最近的照片: PhotoKit, newest 120, four columns, numbered badges in tray order. Limited access shows
    "你允許渥屋助理存取的照片" and "更改範圍" (`presentLimitedLibraryPicker`). Without access the panel explains
    and offers "允許存取照片"; the system prompt is raised once automatically the first time the panel opens.
- Tray (`chat.attach.tray`): photos as 58 pt squares, files as cards with the Android extension badge colors,
  each with "去掉<name>". At most 9 attachments, photos and files together; each file at most 200 MB; less than
  500 MB free or more than 4 GB in one conversation also refuses. Notices: "一次最多 9 個附件,另外 N 個沒加上",
  "沒能新增:…(單個檔案不超過 200 MB)", with "知道了".
- Send is enabled with words, attachments, or both. While files are still being copied, "+" and send wait and the
  bar says "正在新增附件…". Every send goes through `attemptSend`, so a missing model is explained as before.
- The transcript shows photos (one large, two side by side, or three columns), then file cards, then the words.
  Tapping opens Quick Look; a removed file shows "這個附件已經不在了".

## What the model receives

- The archived prompt is the typed words plus one line per attachment in Android's format without the sandbox
  path: `附件:<name>(<size>)` (sizes "N B", "N KB", "N.N MB"). Later turns therefore know what was shared.
- For the turn that carries them, the app's own copies are read off the main actor (`ChatAttachmentReader`):
  - images become JPEG, long side ≤ 1280 px, quality 0.8 (Android `ModelImage`), sent as `image_url` parts only
    when the saved model is marked "能看圖" (Settings › 模型). Otherwise the prompt gets a note and the chat shows
    "這個模型不能看圖,N 張圖片沒有交給模型。", never a silent drop;
  - text, RTF and PDF (PDFKit) become text parts labelled with the file name, cut to the room left in the
    64 KiB chat window (at least 8 KiB, at most 32 KiB per file) with "（內容過長，只附上前面一部分）";
  - anything unreadable (binary, locked PDF, scanned PDF without text) is named with the reason.
- `ModelMessage.attachments` allows up to nine labelled attachments on one user message. A tool loop (memory,
  profile, MCP) may append its own messages after it, so attachments work with "使用記憶" on (the default).
  Earlier turns are rebuilt from archived text alone, so files are never re-sent.

## Storage

- Copies live in Application Support/ChatAttachments/<archive scope>/<conversation>/<attachment id>/<name>,
  excluded from backups; UI tests use the isolated `test-<UUID>` scope of the conversation archive.
- Archived turns keep only metadata (`ArchivedAttachment`); old rows decode unchanged and rows without
  attachments keep their previous encoding. Deleting a conversation deletes its files except those a branch made
  from it still shows. A new or different conversation clears the unsent tray, as on Android.

## Not done / differences

- Archive titles of attachment-only first messages show the "附件:" line (Android titles them "照片", "N 張照片", …).
- iOS asks for camera and photo library permission; Android's camera intent needs none.
- Android-only phone control features are out of scope.
