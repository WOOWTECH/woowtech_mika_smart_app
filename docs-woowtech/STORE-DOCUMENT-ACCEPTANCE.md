# Android Play-channel document integration

This candidate integrates the existing shared HTML/PDF/CSV implementation into both Play package IDs:
`io.woowtech.assistant` and `com.apporo.assistant.play`. It is based on Play alignment commit `7cb0abf9`, with
Apporo's flavor and identity restored from `6dc10a4e` and `b0e762c1`. Package IDs, version sequences and signing
configuration remain unchanged. It is not a Google Play publication.

## One shared implementation

The document model, tool schema, Android PDF renderer and file viewer match direct-channel commit `2e0410b9`
byte for byte. The shared implementation and delivery corrections were cherry-picked, not rewritten as another
document engine. Evidence: `build/store-document-acceptance/shared-source-equivalence.json`.

The Play branch already supplies `AndroidSandbox.filesOnly` to both parent and child tasks. Despite the historical
class name, this port only accesses the conversation workspace and exports attachments; `runsCommands=false`.
It is ready without downloading or preparing a Linux runtime. The shared `create_document` adapter uses this
port's guarded file operations and native PDF renderer, followed by the existing `share_file` attachment delivery.
It does not require command execution, a script, `SandboxService`, phone control, or a local MCP listener.

Two integration corrections are included:

- Keep file-only capabilities unfolded. Adding `create_document` as an entry tool otherwise hid the pre-existing
  read/search/write/share tools. Executable direct-channel capability folding remains unchanged.
- Apply mandatory payment confirmation through `PLAY_EDITION`, so Apporo's restored Play flavor gets the same
  rule as WOOWTECH, including autonomous mode.

The workspace prompt now explains native document generation and truthful delivery states. Generated files become
previewable conversation attachments; Save a copy uses the system document picker, and Share opens the system chooser.
Neither operation implies a public website or confirmed delivery to another person. Existing format limits and CSV
formula protection are documented in `DOCUMENT-EXPORT.md`.

## Validation

Shared engine tests are referenced from the direct-channel evidence rather than counted as new Play results.
This branch adds channel integration checks and uses the same Android viewer tests on each distinct Play APK.

- First channel run: 16/18 passed. The new entry tool exposed the folding regression above; the other failure was
  a macOS `/var` versus `/private/var` canonical-path assertion. Both corrected; the original failure evidence is retained.
- Corrected channel run: 18/18 passed (`WorkspaceFilesTest`: 6; `WoowtechManifestTest`: 12).
- Canonical compiler-download CI fixes from `0216f899`/`8f6b5974` are reused; their 10 Python tests pass.
- Brand JVM tests passed: WOOWTECH 5/5 (file-only port, transport, AI rules, payment policy); Apporo Play 3/3 (transport, AI rules, payment policy). APK builds, physical-device tests and real conversation acceptance are still in progress.

Local evidence is in `build/store-document-acceptance/` (private, ignored by Git). No real credentials belong in
this report or the repository. Source fingerprints, build logs and test XML identify the exact accepted inputs.

This does not claim Play delivery/signing, store approval, iOS acceptance, all third-party spreadsheet compatibility,
or external contact/cloud delivery. The store integration owner retains responsibility for the final channel/build
matrix, version bump, signing and publication.
