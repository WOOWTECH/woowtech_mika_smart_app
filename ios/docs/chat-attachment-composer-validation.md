# General attachment composer candidate

This candidate is based on development commit `ca6c36c54fab0d0f6a892b3a7dcf2f16b884d267` (which contains `55edf2caee8514745a8e53691cfa3289fcef855d`) and includes the attachment session safety fixes. It adds a separate general attachment control beside the existing PDF and voice controls. The attachment remains tied to the current session; the review identifies the destination and additional request data, and it must be confirmed again after changes. A failed selection remains a pending decision until replacement or explicit removal. The user can explicitly remove the attachment; switching to the data screen retains it in memory, while backgrounding discards it or cancels its request. Starting another conversation requires removing it first, and the text draft is retained.

For this phase, one attachment is sent only through the ordinary model path. MCP and the global Use memory setting must be turned off before confirmation and sending; the UI explains that the global change affects other conversations and keeps the draft. The attachment path does not run automatic memory extraction. Approved skill context may still be sent and is disclosed in the review. This is a restricted subset, not complete Android parity. No existing model configuration explicitly declares image support, so images can be selected and validated but cannot yet be confirmed for sending. A future model-capability flow must establish this without inferring support from a name.

The review states that the full attachment goes to the chosen model service. The archive does not store the original attachment, selected URL or filename, but a completed answer can contain attachment-derived data and may be saved, quoted or sent in later history. Filenames, destination URLs and answers can themselves contain personal data. They are presented as appropriate and must not be logged.

## Simulator validation, not yet run

On a Mac with Xcode and a disposable iOS simulator, from `ios/`:

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -only-testing:WoowAssistantUITests/ChatAttachmentComposerUITests \
  -only-testing:WoowAssistantUITests/ChatVoiceUITests test
```

The attachment suite uses an explicit simulator-only Debug flag and a new UUID namespace for the isolated model settings, Keychain, archive and learning stores. Its temporary synthetic text files use random names; the fake model checks the exact synthetic attachment and returns a fixed marker or a controllable failure/cancellation. It does not use a real account, model, network or user file. One case opens the system document picker and cancels; the synthetic selection buttons exercise the real presenter and bounded reader but do not prove third-party provider or security-scoped picker behavior. Accessibility assertions check identifiers and localized labels, not the VoiceOver service. `python3 scripts/check_attachment_composer_fixture.py` checks flag isolation and standalone Release-object exclusion; the packaged app and native builds still need validation.

Native reviewers should also test a third-party provider and security-scope release, valid and corrupt JPEG/PNG full decoding, file and image limits, cancellation during provider reads, switching away and backgrounding, dynamic type and VoiceOver, interaction with voice and PDF, and the success/failure behavior of an explicitly configured compatible service under an independently authorized test plan. This candidate does not establish service compatibility or real-device behavior.
