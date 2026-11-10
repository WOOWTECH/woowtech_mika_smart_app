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

Local source checks: Apporo branding/resource contracts and translation validation pass; the Python CLI suite passes 58 tests. JVM, build and Apporo Android runtime results will be recorded after execution. The WOOWTECH report's aggregated 587 instrumentation passes are not an Apporo result.

The targeted device acceptance covers branded UI, real WebView actions/uploads, approval refresh and isolation, and wheel selection. Scripted model tests verify deterministic Android behavior; separate actual-model tasks are needed to assess task completion through the computer interface.

## Limits retained

PR #11's proposed fixed 15-minute / 2-million-token cutoff remains excluded. This change does not establish a fair three-way long-conversation performance comparison. Physical microphone recognition, actual speaker sound and OEM installation verdicts require separate real-phone evidence. Memory search currently targets active records; pending skill drafts are managed separately.

This document describes a candidate, not a published release. Apporo's package, English default, visual identity, release certificate and independent update channel remain unchanged.
