# Android Play-channel document integration

This candidate integrates the existing shared HTML/PDF/CSV implementation into both Play package IDs:
`io.woowtech.assistant` and `com.apporo.assistant.play`. It is based on Play alignment commit `7cb0abf9`, with
Apporo's flavor and identity restored from `6dc10a4e` and `b0e762c1`. Package IDs, version sequences and signing
configuration remain unchanged in the original acceptance build. The subsequent signed release submission is recorded below; submission is not Google approval or delivery to a device.

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
- Brand JVM tests passed: WOOWTECH 5/5 (file-only port, transport, AI rules, payment policy); Apporo Play 3/3 (transport, AI rules, payment policy). Additional MCP/provider-policy checks passed 3/3 on each brand.
- Both debug APKs and both test APKs built successfully. Runtime source is `c9fbb5d8`; the later test-only correction attaches the same lazy browser surface used by Play tasks. Document execution must not initialize it.
- POCO C85, Android 15: both existing store packages were updated with matching local acceptance signatures, preserving first-install timestamps. Pulled installed APK bytes exactly match the built artifacts. These are store-channel debug acceptance APKs installed through ADB, not Google Play delivery.
- WOOWTECH: initial run 13/14 passed; the new workflow test omitted the required browser surface. Corrected that fixture and reran its single failing case successfully. The other 13 cases were not repeated. Apporo: 14/14 passed in one run with the corrected fixture.
- Device cases cover native HTML/PDF/CSV generation through the real file-only port/tool executor, readable exported attachment URIs, Chinese multipage PDF, oversize failure, previews, actual system Save a copy writes, cancel, unsupported-file handling, and three external-share receiver cases. Shared bytes were read in a separate test-APK process and compared exactly; no contact or cloud service received files.
- MIUI blocked background test-activity starts. The host brought only the test activity forward and recorded these interventions; background permissions were not relaxed. Both test APKs were removed after execution. The six format/brand preview screenshots were visually checked for readable Chinese content.
- Full CI core JVM and both brand builds passed; Apporo startup smoke passed API 30/32/35/36. CI still fails existing translation resource consistency checks and the English accessibility test that expects a service removed from the Play manifest. These are not counted as document acceptance passes. Failed logs and the API 35 instrumentation artifact are retained.

## Ordinary conversations and actual attachment delivery

Both brands completed the same ordinary request for a Traditional Chinese report with two rows, an HTML attachment,
a PDF attachment and a CSV attachment. The request did not name `create_document` or `share_file`.
Each task trace shows three successful native `create_document` calls followed by three successful `share_file`
calls, with no executable runtime tools. Existing logins and model settings were retained.

| Brand | Conversation | Result | Elapsed | Generated HTML / PDF / CSV |
| --- | --- | --- | --- | --- |
| Apporo Play | `b01a3a09-dbbe-4dfa-b0b1-b37f38a1f44c` | succeeded / done | 52 seconds | 930 / 68,967 / 83 bytes |
| WOOWTECH Play | `f2705b38-9cbf-4fb7-b00e-571a072139d7` | succeeded / done | 2 minutes 40 seconds | 958 / 67,135 / 83 bytes |

All six actual conversation cards were opened on POCO and their previews visually checked. Chinese text and both
table rows were readable in the PDF and HTML; CSV retained the comma-containing note as one field. Each actual
attachment then went through Android's system Save a copy picker. All six pulled saved copies were byte-for-byte
equal to their original attachments. The files remain in Downloads as `doc-qa-20261121-1708.*` (Apporo) and
`doc-qa-20261121-1710.*` (WOOWTECH), as well as their original brand download folders.

Evidence: `{apporo,woowtech}-conversation/verification.json`, task events, original and saved files, and
`{apporo,woow}-chat-{html,pdf,csv}-preview.png` under the private evidence directory. The external-share receiver
checks above used separate synthetic sample files; these real conversation files were previewed and saved, not
sent to an external contact. PDF rendering on this phone does not guarantee every other reader's font compatibility.

One preliminary Apporo request was corrupted by the Chinese keyboard during automated text entry. The model asked
for clarification, and that test was cancelled. After temporarily selecting the English keyboard and verifying the
entire typed request before sending, both accepted conversations completed. This failed input attempt is not counted
as document acceptance. The original keyboard, orientation and app locales are restored after testing.

Local evidence is in `build/store-document-acceptance/` (private, ignored by Git). No real credentials belong in
this report or the repository. Source fingerprints, build logs and test XML identify the exact accepted inputs.

This does not claim Play delivery/signing, store approval, iOS acceptance, all third-party spreadsheet compatibility,
or external contact/cloud delivery. The store integration owner retains responsibility for the final channel/build
matrix, version bump, signing and publication.


## Signed production update submission — 2026-11-21

Release source: `3db759327eaa67327d01cd03eefbd8ec69a09ac2` (only version metadata changed after the device acceptance source). WOOWTECH is `io.woowtech.assistant`, version `0.1.37-play.4`, code 4. Apporo is `com.apporo.assistant.play`, version `0.1.37-play.2`, code 2.

Both release AABs were signed with their existing upload keys and accepted by Google Play Console. `jarsigner`, `bundletool validate`, certificate comparison, manifest identity/version/debuggable checks, 16 KB page alignment and excluded direct-channel components all passed. No Linux runtime assets, accessibility/phone-control/sandbox services or direct APK-install/all-packages/overlay/all-files permissions were found. Targeted `*Play*Test` checks passed 6/6 on each brand. An initial incorrectly scoped Gradle invocation also ran the broader WOOW suite and failed 17 direct-only/known locale expectations; its log and results are retained, not reported as a full-suite pass.

- WOOW AAB SHA-256: `4b98a21edf1d26e71306990d1801d52ce6584f9c7f6bccde2288a76ac11a162e`.
- Apporo AAB SHA-256: `82be354fbac7beb433da0c3c2cd82c733457437a3dc3800b8a4a9dea1df74d94`.
- Private artifact/certificate/manifest receipts: `~/.local/share/woowtech-mika/release/document-update-20261121/verified-bundles.json`.

Both production updates were submitted for 100% rollout within their existing countries. Both submissions subsequently passed the automated quick checks and Console showed “Changes are in review”. This is not approval or public availability. Nonblocking warnings concern missing mapping/native debug-symbol files. The previously entered WOOW app-access instructions were preserved. Screenshots and text are in `build/store-document-acceptance/*submission.*`.

The public Android privacy notices and homepage descriptions were updated from source `dbcc2b37` on `release/play-privacy-20261121` for optional xAI/OpenRouter login, relay access and locally generated/exported documents. Both Workers passed type checks and smoke tests. Production policy content, unchanged iOS policy content, GET/HEAD/CSS, health, reviewer video and existing OAuth redirect paths were checked. Deployments: WOOW `a70a9ae8-2dca-4406-a7e2-5a01218e8d56`; Apporo `449225d5-c10d-4ea1-9ed8-de40d951fd22`. Private receipts are in `assistant-play-privacy-20261121/build/privacy-release/`.

POCO still holds the earlier store-channel debug acceptance APKs. Google Play's distribution signing and download/update path have not been validated on POCO; no existing package/data was removed to change signatures. Approval and availability remain controlled by Google.
