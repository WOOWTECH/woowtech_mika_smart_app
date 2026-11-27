# Align the Play edition with the direct-download edition

Owner decision, 2026-11-18: the Play edition of 渥屋助理 follows the direct-download edition for models, chat, memory, skills, browser, MCP and everything else except phone control.

- Play edition: `playstore/woowtech-compliant-20261111` at `964d7bec`.
- Direct-download edition: `main`. The latest public release is `v0.1.37-woow.10` at `b3a5fe0d`.
- Work on `woowtech/play-xai-signin`, which already offers xAI / Grok sign-in. Make one small commit per item below; CI runs on `woowtech/**`.

Findings come from reading the code. CI builds and tests the work (see Status); nothing has been tried on a phone yet.

## Status, 2026-11-18

Done on `woowtech/play-xai-signin` (draft PR #42 into the Play branch, not merged). Items 8 and 9 are also on `woowtech/main-reply-limits` for the direct-download edition (draft PR #43 into `main`, not merged). Nothing was built locally; CI is the only check, and nothing has been tried on a phone.

| # | What changed | Commit | Unit tests |
|---|---|---|---|
| CI | The Play branch failed CI before this work, so its unit tests never ran: fixed the device-test compile, `SingleEntryTest` (`permits` renamed to `allows`), the roles prompt size and `ManifestProvidersTest` | `b035028d`, `66741445` | |
| 1 | A files-only workspace (`AndroidSandbox.filesOnly`, `SandboxPort.runsCommands = false`): `read_file`, `write_file`, `search_files`, `share_file`, and no `run_command` or skill scripts. `read_file` gives photos to the model as images (HEIC, HEIF, GIF, BMP and photos over the size limit are re-encoded as JPEG first, with EXIF rotation applied) and reads the text of PDF, Word, Excel and PowerPoint files (`DocumentText`, page, sheet and slide markers, paging with `offset` and `limit`). New prompt `capabilities/workspace.md` | `baf4e755`, `d36986ae` | `WorkspaceFilesTest`, `DocumentTextTest`, `FilesOnlySandboxTest` |
| 2 | The task card says which MCP servers could not connect | `a4cc41f9` | `McpRunNoticeTest` |
| 3 | Sign-in offers ChatGPT, xAI / Grok and OpenRouter. `privacy-play.ts` covers xAI and OpenRouter (effective date 2026-11-18). Not deployed | `227dcbc1` | `AccountSignInKindsTest`, relay worker smoke test |
| 4 | Autonomous mode and "let the assistant change its own settings" are back under During work. In this edition a payment always asks first, autonomous or not; a run started in autonomous mode still has the confirmation gate, and only the paying step stops. Self-settings offer appearance and keep screen on only | `57792daf`, `3b85ebcb` | `PaymentsAlwaysAskTest` (7 cases), `ApprovalStoreTest`, `SelfConfigImplTest` |
| 5 | The page the user asked to keep stays open after the task, for at most two hours; the `TaskService` foreground-service text says so | `e4139bbe` | `WoowtechManifestTest` |
| 6 | Scheduled tasks with `SCHEDULE_EXACT_ALARM` (no `USE_EXACT_ALARM`), re-armed after boot, update and time changes by a new `ScheduleRestoreReceiver` that never starts phone recovery. As in `main`, only runs the user starts in the app can create or change schedules | `80a57bd3` | `WoowtechManifestTest`, `ScheduleRestoreReceiverTest`, `brand-check.sh` |
| 7 | Scheduled tasks entry in the drawer, also in the short landscape layout | `8dc98ada` | drawer device test (compiled only) |
| 8 | The Anthropic reply limit comes from the model list's `max_tokens`, or the known Claude family limit, capped at 32K when streaming, 16K when not, and a quarter of the context window. Unknown models keep the old 4096 (16000 with adaptive thinking) | `8b1f4961` (main: `eaa8da26`) | `AnthropicModelTest`, `ModelCatalogTest`, `ReasoningSettingsTest` |
| 9 | While a model request is retried, the task card says "Connection lost. Trying again (attempt N)…" or "The model service is busy. Trying again (attempt N)…", in all ten UI languages | `123f6378` (main: `355a734a`) | `RetryNoticeTest`, `ModelRetryCopyTest` |

### Also closed after a fresh comparison with `main`

Models, chat, memory, skills, browser and MCP were compared file by file with `main` after items 1 to 9. Apart from phone control and the policy rows below, one gap was left, and it is now closed:

| What | Commit | Unit tests |
|---|---|---|
| Connect a computer, as the outbound relay only (the "Computer connection" row below). `McpService` is declared again, not exported, as a `specialUse` foreground service; in this flavor the runtime never listens on the LAN or USB and offers no screen state, wake or unlock. The entry is back in the drawer (long names in the short-screen layout now end with an ellipsis) and in Advanced settings, and the connection resumes when the app starts and after boot or an update. The page offers MCP client setup only, because the CLI guide links to the GitHub repository. `privacy-play.ts` describes the gateway. Not deployed | `3aef7796`, `1989c67b` | `WoowtechManifestTest`, `McpUsbSettingsTest`, `ManifestProvidersTest`, `ScheduleRestoreReceiverTest`, relay worker smoke test |

### CI results

On `1989c67b`, the last code commit (runs 44300434972, 44300435022, 44300425426, 44300434959, 44300435011 and 44300435013):

- Passed: core JVM tests, relay (Go), the relay worker checks (with the privacy page smoke test), the woowtech (Play) APK build in the push and PR runs, brand checks, release plan, the apporo build and the apporo-alignment build. PR #43 (`355a734a`) passed every check.
- app (Android): the app, its debug APK and the device tests compile. 1548 unit tests ran and 3 failed, all in `StringResourcesTest`, on the 406 strings that the base branch has only in English and Traditional Chinese. The CLI translation check reports the same 406, as on the base branch (run 43588774211).
- apporo-alignment `english-runtime` (API 35 and 36): 4 of 5 device tests pass. `ApporoAlignmentTest.englishHelpPersistsUntilRealAccessibilityServiceIsOn` waits for the real accessibility service, which the base branch removed from the manifest in `fe311390` (phone control is out). On the base branch this job never ran, because its device-test build failed (run 43588774213).
- The first attempts of the app job and the PR's APK job stopped on downloads (HTTP 429 from the official Maven repository, HTTP 403 from the Gradle API). Their re-runs got through, with the results above.

### Not done

- Phone control stays out (owner decision). The direct-download features in "Closest version that can ship" below stay out too, because they conflict with Play policy; their Play alternatives are in place (the help page excepted, see below).
- Scanned PDFs (pictures of text) have no text layer; `read_file` says so. Encrypted PDFs and the old binary `.doc`, `.xls` and `.ppt` formats are not read either, and each gives a clear error. Showing scanned pages to vision models would need page rendering, which needs a phone to test.
- The built-in `documents` skill still describes its script; in this edition the model is told scripts are unavailable and `read_file` reads PDFs directly.
- The help page that would replace the GitHub link is not built: it needs content from the owner and a Worker deployment.
- `StringResourcesTest` and the `tools/i18n` check fail on 406 strings that the base branch has only in English and Traditional Chinese (same count on base, PR #38 run 43588774211). Not changed here.

## Work, in order

| # | Item | Where | How |
|---|---|---|---|
| 1 | **Attachments reach the model.** Attachments are only named as `/workspace/inbox/...` text, and the Play edition passes `sandbox = null`, so the model has no `read_file`. | `SandboxCapability.kt`, `TaskTools.kt:138`, `TaskRun.kt:791,823`, new no-execution workspace | Offer the file tools without any command execution. Prove it by sending a real photo. PDF and Office files need text extraction as well. |
| 2 | MCP connection failure notice | `TaskRun.kt:777` | Bring back `main` `TaskRun.kt:781-788`, removed in `fe311390` |
| 3 | ChatGPT, xAI / Grok and OpenRouter sign-in | `AccountSignIn.kt:89`, `tools/woowtech-relay-worker/src/privacy-play.ts` | Remove the Play limit and add xAI and OpenRouter to the privacy policy text |
| 4 | Autonomous mode and letting the assistant change its own settings | `SettingsSubPages.kt` (`main` lines 209 and 241), `ApprovalStore.kt` | Bring back the settings. **Owner decision: in this edition, payments always ask first, even in autonomous mode.** Add a test for that rule. |
| 5 | Keep the web page after a task | `WebStack.kt:205`, `AndroidManifest.xml:118` | Reverse that part of `b3197afa` |
| 6 | Scheduled tasks | `AndroidManifest.xml`, `MikaApp.kt`, `TaskRun.kt:777,830` | Partly reverse `fe311390` and `3a80dbb5`. Use `SCHEDULE_EXACT_ALARM`, not `USE_EXACT_ALARM`. Do not reuse `BootRestoreHandler`, which starts phone recovery. |
| 7 | Plans entry in the drawer | `ChatDrawer.kt:276,293` | Bring over `main` line 248 |
| 8 | Long Anthropic replies | `AnthropicModel.kt:372` | Set the output limit from the model instead of the fixed 4096. Fix both editions. |
| 9 | Network failure feedback | `ProviderStore.kt:1129`, `RetryPolicy.kt:16` | Show that a retry is happening. Today a dead connection can stay silent for about 8 minutes. Fix both editions. |

## Closest version that can ship

These direct-download features conflict with Google Play policy. Build the alternative instead.

| Direct-download feature | Policy area | Play edition |
|---|---|---|
| Linux sandbox, skill scripts, stdio MCP | Device and Network Abuse (executable code) | File tools and remote HTTPS MCP |
| HTTP to LAN services and pages | User Data (secure transmission) | HTTPS only, except this phone itself |
| Computer connection | Foreground service, remote control | Outbound relay with no device permissions |
| Recent photos grid | Photo and Video Permissions | System photo picker |
| In-app update | Request Install Packages | Updates through Google Play |
| GitHub link | Unclear for a repository that offers APKs | A help page with no APK |

Stays out by owner decision: Accessibility control, OCR, ADB helper, root, floating capsule, remote wake and unlock, app access list, mute, operation pace, and phone setup guides.

Keep what only the Play edition has: AI response reports, the safety prompt and the privacy policy entry.

## Check on a real Android phone

These problems were found on iPhone. Check whether the Play edition has them too:

- The home screen example that finds AI news in the built-in browser
- Leaving the app while a reply streams, then returning
- Attaching a photo and asking what it shows
- Markdown tables and code blocks
- A task-finished notification while the app is open on that chat
- The drawer in portrait and in landscape with a notch

New in this round:

- Photos: a JPEG, a HEIC, a very large photo and one taken sideways (EXIF rotation). Ask what each shows.
- Documents: a text PDF, a Chinese PDF, a scanned PDF, and Word, Excel and PowerPoint files. Ask about their content; a long PDF should be read in parts.
- An MCP server that cannot connect: the task card names it.
- ChatGPT, xAI / Grok and OpenRouter sign-in. The owner signs in.
- Autonomous mode on: sending a message goes ahead without asking; paying or placing an order still asks. Ask the assistant to switch to the dark appearance.
- Keep a page after a task: it stays open, with its notification, for at most two hours.
- A scheduled task after granting "Alarms & reminders", after a reboot and after a time zone change.
- The scheduled tasks and Connect a computer entries in the drawer.
- A long Claude answer (well over 4,096 tokens) is not cut off.
- Airplane mode while a reply is coming: the task card says it is retrying.
- Connect a computer: pair with `assistant-relay.woowtech.io`, turn on remote access, connect an MCP client on a computer, send a task, check the ongoing notification, reboot and update the app and check it reconnects, then unpair.

## Before any release

- Raise `versionCode` (now 3) and the `-play` version name.
- Deploy the updated privacy policy.
- Update `PLAY_DATA_SAFETY_WORKSHEET_2026-11-12.md`, which still says custom endpoints are unavailable, and the Data safety form.
- Update the Play Console foreground service declarations and demo video for items 5 and 6, and the sign-in service description.
- Declare the new `McpService` foreground service (`specialUse`, Connect a computer through the relay) in Play Console, with a demo video.
- The updated privacy policy now also covers the remote gateway. Add the gateway's data flows (task content, replies, conversation reads, the computer's IP address, through WOOWTECH's relay) to the Data safety form.
- Update the store listing text.

Do not merge into the Play branch, upload to Google Play, or deploy the privacy policy without the owner's approval. The owner completes every real sign-in and enters every password, code and key personally.
