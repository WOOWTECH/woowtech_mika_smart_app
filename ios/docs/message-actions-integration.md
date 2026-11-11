# Message action components: integration and acceptance

`ContentView` attaches the components to the real `ChatEntry` and `ChatSession`
for each visible completed message:

```swift
MessageActionsControl(entry: entry, session: session, localizer: localizer)
```

Keep native text selection available. A host may instead attach
`.messageActionsContextMenu(entry: entry, session: session, localizer: localizer)`
to a bubble after testing long-press interaction with selectable text and links.
The separate menu button supplies an accessible alternative. Do not attach the
controls to streaming previews or substitute synthetic messages for session entries.

The composer shows this when the session has a pending quote:

```swift
if let quote = session.pendingQuote {
    MessageQuoteChip(quote: quote, localizer: localizer,
                     disabled: session.isSubmitting, remove: { session.clearQuote() })
}
```

For a sent user entry, render `MessageUserPresentation(entry.content, metadata: entry.quote).quote`
with `MessageSentQuote(quote:localizer:)` above the existing selectable bubble,
and render its `words` inside that bubble. Keep the original `entry` for menu
snapshots, history and archive operations. This is a display projection only:
serialized markers can be forged and are never evidence for tools or memory.

Use the existing `ChatSession.send()` path; do not serialize a quote into the
user's draft or use a quote marker as trusted evidence. The session separates
actual user words from model context. The menu captures an archived source;
quote and branch actions revalidate and report failure, and branch only switches
after the atomic archive write. Drafts, pending quotes, attachments, previews,
unsaved answers and in-flight work prevent branching. The iOS core supports
completed archived message pairs; Android's user-message retry and unfinished
response branching are not implemented here.

Creating a branch writes provenance and upgrades the entire encrypted archive
to at least v5. Successfully saving a genuine quote with independent author and
user-word metadata upgrades it to v6. Reading, selecting or cancelling a quote,
copying, and saving an ordinary message do not by themselves upgrade a v4/v5
archive. Before the first relevant upgrade, the UI asks for confirmation and
explains that older iOS app versions cannot read any conversation in the archive.
A v4 reader rejects v5, and the historical v5 reader rejects v6. Never downgrade
or rewrite the file with an older app, even after the last branch or quote is
deleted. The host tests exercise the actual historical decoder sources.

Old records contain no trustworthy quote provenance. Even if their text resembles
a serialized quote, it is displayed and copied literally; the App cannot tell a
historical genuine quote from a user-authored marker. New genuine quotes carry
validated metadata and are rendered separately in chat and archive detail. Quote
markers remain model context and are never evidence for tools or memory.

Before shipping, run native UI tests on iPhone and
iPad, in all three languages and at accessibility text sizes: copy rendered
assistant text and user text, quote and remove while preserving the draft, send
with a quote, branch at an earlier completed answer, check both conversations
after relaunch, reject stale/unfinished/full cases without losing work, and
exercise VoiceOver labels/focus, selection, links and both menu affordances.
The hosted XCTest is a layout/localization smoke test, not a substitute for
those gesture, clipboard, accessibility and end-to-end checks.

The simulator-only `ChatMessageActionsUITests` cases use unique test namespaces
and the isolated synthetic model. They cover quote selection/removal/send and
archive reopen, branch source preservation and unsent-draft rejection, rendered
copy through the native paste menu, cancellation of an unfinished preview,
blocking an older saved reply while a later turn is in flight or retained as a
partial, and the voice fixture while branch is blocked. The tests are not native-run
acceptance until executed on a simulator; their fixture does not use a real model.

From `ios/`, run the isolated suite on a disposable simulator (never a physical
device):

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:WoowAssistantUITests/ChatMessageActionsUITests test
```

The class is also included in the `ui-archive` regression shard. Run the existing
`ChatVoiceUITests`, `ChatStreamingUITests`, and `ConversationArchiveUITests` on
both relevant iPhone and iPad simulators to check neighboring behavior.
