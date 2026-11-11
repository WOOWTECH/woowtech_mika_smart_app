# Message action components: integration and acceptance

These components are intentionally not attached to `ContentView`. The host must
pass the real `ChatEntry` and `ChatSession` for each visible completed message:

```swift
MessageActionsControl(entry: entry, session: session, localizer: localizer)
```

Keep native text selection available. A host may instead attach
`.messageActionsContextMenu(entry: entry, session: session, localizer: localizer)`
to a bubble after testing long-press interaction with selectable text and links.
The separate menu button supplies an accessible alternative. Do not attach the
controls to streaming previews or substitute synthetic messages for session entries.

Place this above the composer when the session has a pending quote:

```swift
if let quote = session.pendingQuote {
    MessageQuoteChip(quote: quote, localizer: localizer,
                     disabled: session.isSubmitting, remove: { session.clearQuote() })
}
```

Use the existing `ChatSession.send()` path; do not serialize a quote into the
user's draft or use a quote marker as trusted evidence. The session separates
actual user words from model context. The menu captures an archived source;
quote and branch actions revalidate and report failure, and branch only switches
after the atomic archive write. Drafts, pending quotes, attachments, previews,
unsaved answers and in-flight work prevent branching. The iOS core supports
completed archived message pairs; Android's user-message retry and unfinished
response branching are not implemented here.

Creating a branch writes provenance and upgrades the encrypted archive to v5.
Ordinary reading, quoting, copying and non-branch saves do not by themselves
upgrade it to v5. An old v4 iOS reader must reject a v5 archive; **do not open or
rewrite it with an older app**. Removing a branch does not downgrade the version.

Before shipping, integrate the controls and run native UI tests on iPhone and
iPad, in all three languages and at accessibility text sizes: copy rendered
assistant text and user text, quote and remove while preserving the draft, send
with a quote, branch at an earlier completed answer, check both conversations
after relaunch, reject stale/unfinished/full cases without losing work, and
exercise VoiceOver labels/focus, selection, links and both menu affordances.
The hosted XCTest is a layout/localization smoke test, not a substitute for
those gesture, clipboard, accessibility and end-to-end checks.
