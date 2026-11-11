# Standalone chat attachment picker and review

This stage adds `ChatAttachmentPickerView`, its host-owned view model and
`ChatAttachmentPresenter`. It is not presented by the current app and does not
invoke a model, create a request, save an attachment, or expose selected bytes
in view state. Its system Files picker offers JPEG, PNG and supported UTF-8
text files; this is not a Photos-library picker or a PDF flow. Choosing a file
starts local import immediately. The sheet displays its sanitized name, actual
size, progress, errors, and a destination review; confirmation itself does not
send. Dismissing the sheet retains the host-owned staged selection.

`picked(_:)` must be called synchronously only from a successful picker callback.
It acquires a security scope immediately, before starting asynchronous work.
The scoped reader closes it exactly once after the real coordinated read returns;
if cancellation wins before read begins it closes immediately and blocks a late
read. A provider that ignores cancellation may keep the scope until it returns.
A failed scope acquisition is allowed for already-accessible local URLs; the
coordinated reader still checks actual file access. No security bookmark is
created. The strict inode and image-decoding restrictions in
`chat-attachment-import-core.md` remain in effect.

Before a review can be confirmed, the host must supply a
`ChatAttachmentReviewContext`: HTTPS destination, model, vision capability,
credential revision, input revision and the fixed categories of *all* other
information sent alongside the attachment. Arbitrary file contents cannot be
provided as display labels. It must rotate the relevant revision
and call `updateContext` for every prompt, conversation, credential, endpoint,
model, selected references or transmission-policy change. This revokes approval.
For an image, unknown/unsupported vision blocks confirmation. A supported flag
is the host's declaration, not proof that a model service accepts the image.

The host must re-check the exact live context immediately before calling
`takeConfirmed(context:)` and again after it returns and immediately before
starting network I/O; a change across the async boundary discards the value and
requires reselection/review. After `takeConfirmed` returns, only the caller can
clear its copy; no API here sends or revokes that copy. Preserve the current
draft and show errors on failure. Do not automatically replay a consumed
attachment in another request or conversation. Discard the presenter on draft
abandonment, conversation switch, logout/background or other host policy event.
Coordinate this with new-conversation protection and the existing PDF flow.
The host must also define explicit retry and disclosure behavior before wiring
this into `ChatSession` or the composer.

Run `python3 ios/scripts/check_chat_attachment_presenter.py`. The script compiles
the actual presenter, scope adapter and standalone SwiftUI view, then runs
synthetic local/injected tests without network. It typechecks against macOS
SwiftUI; iOS SDK/Xcode builds, the native picker, sandbox entitlements,
third-party providers, lifecycle transitions, VoiceOver and model integration
remain unverified. Fake image decoding used in the presenter test is only a
lifecycle fixture; real ImageIO decoding is covered by the import-core tests.
