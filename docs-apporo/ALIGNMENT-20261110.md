# Apporo Assistant apporo.5 functional alignment

Candidate `0.1.37-apporo.5` / `3805` integrates the additional WOOWTECH functional fixes through `b92c5683` into Apporo's released apporo.4 source. The source conversation is [WOOWTECH functional acceptance](https://omnigent.woowtech.io/c/d4f2bde9acf641e9b696176607c399cb?message=codex_01a1c3cd-6470-7f71-8535-fd0528ff6209). Its POCO results are supporting evidence; they are not counted as Apporo tests.

## Changes carried into Apporo

| Area | Resulting behavior |
| --- | --- |
| Memory deletion | `memory_forget` removes a named record only when its ID, current content and quoted current-user request agree. It is unavailable to read-only, child and unattended tasks. Deleted references are stripped and the existing undo mechanism records the change. Explicit deletion prevents the same run's automatic extraction from immediately saving it again. |
| Assistant identity | Main and child prompts identify the actual installed package. Requests about this assistant's memory/settings should not open Mika or another branded installation. Apporo's English memory-save rules remain intact. |
| App launch recovery | A wrong foreground after launch gets a bounded recovery rather than repeated observation/listing without progress. |
| File upload | Stable browser references are resolved to WebPort references before upload. Tests inspect the actual received file content. |
| Web settling | The settling deadline includes the whole JavaScript polling operation, including slow callbacks. It is not a new whole-task deadline. |
| Wheel selection | Accessibility scroll steps wait for UI settling. A missing value that wraps back without a match terminates instead of repeatedly scrolling or dragging. |
| Approval notifications | Refreshing the same request updates its existing PendingIntent. A previous request cannot act on a different request. Apporo retains View and Decline notification actions; approval still requires the full card. |
| Phone lifecycle | PIN-field classification avoids treating the PIN container as a second password field. Force-stop recovery, authenticator ownership and stale-screen evidence have regression coverage. |
| Build and UI | Main-thread Toast dispatch, flow subscription and API guards carry over. AGP 8.8.2 supports the full lint checks without suppressing their findings. |

The integration also finalizes explicit memory changes from computer-origin tasks before result delivery: reference cleanup and undo notes must not depend on notification or outcome-judging success. This does not enable remote automatic memory extraction or skill drafting.

## Apporo integration details

Instrumentation resolves the test package from Android rather than assuming Mika's package. English confirmation tests retain the safer Apporo notification actions. Duplicate translation resources introduced by merging the older WOOWTECH branch are removed while preserving Apporo's existing accessibility and speech wording. The five branded UI cases additionally check the installed Apporo version, prompt identity and English memory-deletion label.

## Validation status

Local source checks: Apporo branding/resource contracts and translation validation pass; the Python CLI suite passes 58 tests. [PR #13](https://github.com/WOOWTECH/woowtech_mika_smart_app/pull/13) has 14 successful checks, including core JVM, Android JVM/device-test compilation, CLI, relay integration, both branded builds, English Apporo runtime acceptance and startup smoke checks. GPL packaging is intentionally skipped for this pull request. The WOOWTECH report's aggregated 587 instrumentation passes are not an Apporo result.

Tested source is PR merge tree `0fd55bbd191097e115be21055c08d73dd8a555e7`, with branch head `8bc7762d6a9ca2fb40cc481f27410fd24596e641`. Local Android is API 36 ARM64 (`emulator-5554`). Cloud English UI tests use API 35/36 x86_64. Apporo's package and version are asserted on device.

| Acceptance | Passed | Skipped | Evidence |
| --- | ---: | ---: | --- |
| Cloud branded English UI | 5 on API 35 + 5 on API 36 | 0 | [Alignment workflow](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/42760651290) |
| ARM64 branded UI/accessibility/fake speech | 5 | 0 | Real Compose UI and accessibility binding; microphone input is simulated. |
| ARM64 WebView actions | 18 | 0 | Includes stale references, focus theft, obscured controls and a continuously changing page returning within its settling cap. |
| ARM64 downloads/uploads | 6 | 1 | Actual workspace file reaches the page; outside-workspace files are refused. The hard-link case is skipped because this emulator disallows creating the fixture hard link. |
| ARM64 confirmation notifications | 5 | 0 | View does not approve; same-request refresh keeps its previous decline button live; an old request cannot decline a new one. |
| ARM64 wheel selection | 4 | 0 | The locked wheel reaches 40 in 20–24 actions; a missing value terminates without forcing a different value. |
| Actual model through Apporo task API | 6 | 0 | Independent checks below. |

The actual-model route is `apporo/gpt-6.1-sol` on the existing authorized test gateway. The earlier `chatgpt/gpt-6.1-sol` route returned HTTP 401 with upstream `token_expired`, although model listing returned 200. The alternative route passed Apporo's provider probe. This route change means the observations are not a controlled latency comparison with earlier WOOWTECH runs.

| Actual task | Elapsed | Input tokens | Verified result |
| --- | ---: | ---: | --- |
| Save two separate test preferences | 12.7 s | 31,951 | Two successful `memory_save` tool results and two persisted change/undo notes. |
| Delete one preference, keep the other | 19.4 s | 55,276 | Exact ID deleted; another conversation's deleted reference removed; kept reference retained; remote delete/undo note persisted. |
| Search again in a new task | 7.7 s | 21,255 | Only the retained ID is returned. No save or phone-launch tool is called. |
| Compute, write and upload a file | 40.6 s | 195,745 | Exactly one server upload; workspace bytes and received bytes match. The 35-byte file has SHA-256 `b3a7ef336040f742101d4ff95e8a49f4666b5bd21a9fae7900dbf29ecfa51a07`. |
| Remove the remaining test preference | 19.4 s | 54,654 | Successful deletion followed by an empty active-memory search. |
| Deliver the existing file immediately | 8.6 s | 47,010 | Only `share_file` is called; no computation or browsing. The file in Download/Apporo Assistant matches the same bytes/hash. |

These are short deterministic acceptance tasks, not long-conversation or model-quality benchmarks. Model waits account for most of their recorded time. Evidence (receipts, tool events, metrics, screenshots and local fixture logs) is stored under `~/.local/share/apporo-assistant/test-evidence/alignment-20261110/` on the test Mac.

The separately signed release candidate uses Apporo's existing certificate, version code 3805, and SHA-256 `1c7fcc46aa96f0eeda4b403f0255c1e559f8c0e292003b77161fb1f5d4cac449`. On ARM64, the publicly released signed apporo.4 was configured through the normal UI and created a real-model conversation. `adb install -r` then upgraded it to the signed apporo.5 candidate. The app ID and first-install time were retained, the installed APK hash matched the candidate, and a subsequent real-model task recovered the earlier conversation marker, computed 152, read its file back and shared it with verified bytes. This additionally demonstrates that the provider configuration and encrypted credential survived the upgrade.

The first computer-interface discovery immediately after the upgrade returned a transient connection error. The following task submission and a subsequent `connect` succeeded. This observation is retained in the evidence; its precise cause is not established, and this change does not claim to eliminate every startup race.

Normal installation on the POCO returned `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`; Apporo was not installed and the existing WOOWTECH app was retained. The Android result does not establish whether Play Protect, an OEM setting or a user action caused it. No protection was disabled.

## Limits retained

PR #11's proposed fixed 15-minute / 2-million-token cutoff remains excluded. This change does not establish a fair three-way long-conversation performance comparison. Physical microphone recognition, actual speaker sound and OEM installation verdicts require separate real-phone evidence. Memory search currently targets active records; pending skill drafts are managed separately.

This document describes a candidate, not a published release. Apporo's package, English default, visual identity, release certificate and independent update channel remain unchanged.
