# Align the Play edition with the direct-download edition

Owner decision, 2026-11-18: the Play edition of 渥屋助理 follows the direct-download edition for models, chat, memory, skills, browser, MCP and everything else except phone control.

- Play edition: `playstore/woowtech-compliant-20261111` at `964d7bec`.
- Direct-download edition: `main`. The latest public release is `v0.1.37-woow.10` at `b3a5fe0d`.
- Work on `woowtech/play-xai-signin`, which already offers xAI / Grok sign-in. Make one small commit per item below; CI runs on `woowtech/**`.

Findings come from reading the code. Nothing here has been built or tried on a phone yet.

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

## Before any release

- Raise `versionCode` (now 3) and the `-play` version name.
- Deploy the updated privacy policy.
- Update `PLAY_DATA_SAFETY_WORKSHEET_2026-11-12.md`, which still says custom endpoints are unavailable, and the Data safety form.
- Update the Play Console foreground service declarations and demo video for items 5 and 6, and the sign-in service description.
- Update the store listing text.

Do not merge into the Play branch, upload to Google Play, or deploy the privacy policy without the owner's approval. The owner completes every real sign-in and enters every password, code and key personally.
