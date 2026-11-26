# iOS direct woowtechbot variant

This variant continues the accepted local-assistant baseline `4119551e` in a
separate worktree. Android integration reference: `0253a7d2`; native QR pairing
reference: `064395a3` (PR48). The standard `project.yml` does not enable the new
screens. Generate with `project-woowtechbot.yml` to define `WOOWTECHBOT`.

The variant uses `io.woowtech.assistant.bot`, development build 294, so it can be
installed alongside `io.woowtech.assistant`. Their app containers and Keychain
access are separate. Existing local data is not migrated or erased. Build 294
here is not an App Store or TestFlight upload, and does not change the separate
293 release acceptance gate.

## Implemented behavior

- Full-page local conversation list, title/message search, pins, conversation
  identity editor, and quick access to existing MCP, memory/skills, browser,
  files, notifications and settings. Existing chat execution stays in ChatSession.
- Names and icons belong to conversation UUIDs. Uploaded photos become a
  cropped 320-pixel JPEG. Cancelling the editor leaves the saved icon intact.
- Built-in icons have three robot shapes, six colors and three expressions.
  Named or customized drafts appear in history even without text. Deleting a
  draft clears its metadata and parked attachments; untouched empty chats do
  not accumulate against the 300-entry presentation limit.
- Text drafts are encrypted and restored after relaunch. Waiting attachments
  and quote context are parked during in-process conversation switches;
  attachment drafts are not promised across process death. An active task or
  unsaved reply blocks switching. No model request is made by switching.
- Up to 20 named services. Each has its own persistent WKWebsiteDataStore UUID,
  including two services on the same origin. Service WebViews stay in process
  memory while switching. After process death the origin reopens; website
  localStorage persists, while DOM-only drafts depend on the website.
  Login retention follows the website's cookie lifetime; session cookies are
  not converted into permanent credentials by the app.
- Full original mobile website, no proxy, HTML replacement, native JavaScript
  bridge or phone-control authority. Main-frame navigation is pinned to the
  configured origin. User-clicked external HTTPS links require confirmation.
- System file selection, permission prompts for same-origin camera/microphone,
  and the existing bounded WKDownload pipeline for explicit same-origin links:
  confirm, cancel, save, share, attach to local chat, or remove. Blob downloads
  and cross-origin download redirects are not supported.
- Native VisionKit QR scanner and deliberate paste entry. Both accept only
  `https://<this-origin>/pair#code=<6..256 base64url characters>` with no query,
  credentials or extra fields. Only name and origin appear in confirmation;
  the invitation stays in memory until the website consumes it.
- Disconnect closes the view while retaining that profile's website data.
  Logout/removal commits a retired identity before clearing its cookies and
  storage. Logout calls the exact origin's `/api/auth/logout`, rejects redirects,
  and distinguishes confirmed remote revocation from local-only cleanup.
  Retired profiles that WebKit still holds are retried on the next launch.

HTTP requires explicit per-service LAN opt-in. Only private IPv4, IPv6 ULA or
`.local` origins qualify. Loopback, link-local and ambiguous numeric literal
spellings are rejected. The bot plist allows local networking; it does not turn
off ATS globally. This origin policy is not a DNS or WebSocket firewall.

## Notification boundary

The shared event contract validates exactly `v`, `serviceId`, `botId`,
`threadId`, `eventId`, `reason`; event IDs are bounded strings, not necessarily
UUIDs. A target is built only from the saved origin as
`/?thread=<thread>&bot=<bot>`. Unknown/disabled services, malformed fields,
extra URLs, and duplicate handled events are rejected. Dedupe includes service,
bot, thread and event, with a bounded encrypted history.

The existing system notification delegate can route an explicit
`userInfo["woowtechbot"]` dictionary containing these six strings. This is an
iOS routing adapter, not a server registration or delivery claim. It does not
approve actions, call tools, grant notification permission, or register a token.

Android currently uses Firebase and `/api/woowtech/android-push/device` with
`platform=fcm`. There is no iOS Firebase app configuration, APNs entitlement,
APNs credential or iOS registration adapter in this implementation. The app
therefore says remote push is not connected. Completing that integration needs
an agreed iOS Firebase/APNs setup and authenticated backend capability contract.
Existing local assistant notifications are independent.

## Reproducible validation

Generate inside this worktree's iOS directory (or copy its Configuration files
when generating into a separate output directory):

```sh
xcodegen generate --spec ios/project-woowtechbot.yml --project ios
xcodebuild -project ios/WoowAssistant.xcodeproj -scheme WoowAssistant \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /path/to/isolated/DerivedData -jobs 1 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=W4UWZ8NP2P PROVISIONING_PROFILE_SPECIFIER= build
```

Use ad-hoc **simulator** signing for Keychain checks. An unsigned simulator app
can draw its UI while Keychain writes fail; that is not a valid persistence
acceptance test. Physical-device builds require actual development signing.

`Tests/AssistantPersistenceTests/BotServiceTests.swift` covers origin rejection,
strict pairing links, profile isolation/retirement metadata, failed mutations,
avatar validation and target routing/deduplication keys. Those Foundation tests
do not prove WebKit cookie isolation or remote delivery.

For independent UI checks, run `scripts/bot_fixture_server.py --host <private-IP>`
and add that exact origin twice with explicit LAN HTTP consent. Its two fake
identities and cookies exist only for this test; it never connects to PaaS.
Verify signed-out initial state, A/B cookies and website drafts, one-profile
logout, reconnect, relaunch, downloads and external-link cancellation. The
fixture's read-only `/test/audit` reports fake identity status without cookies.
Its test login cookie expires after one day so the relaunch check measures a
persistent cookie. The earlier fixture used a session cookie, which correctly
did not survive a process restart.

Native evidence lives outside the repository under
`Documents/WOOWTECH-iOS-validation/woowtechbot-20261126`. Each candidate records
source hashes and the executable SHA256; the UI runner checks both before
testing. A run must exit successfully and finish every requested step. Failed
attempts are retained. The UI driver reads editable values separately from
same-named HTML labels and verifies that switches actually change.

Physical camera scanning, authenticated PaaS/HA pairing, real AI completion and
remote push remain separate acceptance checks. A simulator screenshot or a
synthetic notification must not be reported as those checks passing.

## Validation on 2026-11-26

The final simulator candidate is build-candidate 7, app build 294, executable
SHA256 `6e3833d46f75080cb6e424fb20abf6df297227e6c50a12e827ad045105d93efa`.
It uses the same source hashes recorded in `candidate.json`; test runs verify
the source file set, individual hashes, installed executable and UI driver.

Confirmed on that candidate:

- Independent persistent A/B website cookies and localStorage after app restart.
- Disabling/re-enabling B preserves its login and draft. Signing out A removes
  its local login and draft, allows a fresh login and leaves B intact. Removing
  A removes its service entry while B and the local draft remain. The fixture
  audit confirms three A revocations and one still-active B login.
- Cancelled external navigation and cancelled downloads leave the service open.
- Draft A/B switching, draft deletion, title and icon preservation, cancel-safe
  color editing, conversation search/files screens and existing MCP, memory,
  browser and model-settings navigation (45-step local regression).
- System share completion through Save to Files. The exported file is 43 bytes
  with SHA256 `2e31a8e2da41c1ff30543fb2a16f32322c0d480e0bf49c8af232ee96241b6064`.
  Earlier candidate 5 also passed the direct Save to Files action.
- Original unauthenticated PaaS lab43 page renders inside the service WebView
  and identifies itself as woowtechbot 0.1.169. This proves page loading only.
- Native pairing entry rejects a different origin, requests confirmation for
  the saved origin and cancels without pairing. The simulator displays the
  camera-unavailable fallback. These checks use dummy invitations that are
  never submitted to PaaS.
- Five Foundation tests pass for the shared origin, pairing, service profile,
  mutation, avatar and notification-target contract.

Failed attempts are retained, including the unsigned-simulator Keychain test,
the original session-cookie relaunch expectation, and UI scripts corrected for
the system popover, automatic download-list presentation and Chinese system
share labels. None is counted as a passed run.

`acceptance.json` records nine successful native runs (212 steps), the separate
failed attempts, file-integrity checks and server audit. All nine successful
runs use candidate 7. The temporary fixture was stopped and the test simulator
shut down after this validation.

The physical iPad remains unavailable to Xcode. Real camera decoding,
authenticated PaaS/HA sessions, remote AI completion and iOS remote push have
not passed acceptance. Push additionally requires iOS Firebase/APNs setup;
the app continues to show its unavailable status. No archive or upload was
performed, and the separate standard build 293 release gate is still pending.

The same source also builds successfully for physical iOS with Apple Development
signing. Its signature is valid and the provisioning profile includes the test
iPad. `WOOW-Assistant-Bot-294-development.ipa` is a local development package,
not an installed or accepted physical-device release. `build-device.json` and
`development-package.json` record its signing checks and hashes. The device
executable SHA256 is
`4b479ccaf6ab5bf2c673e7ba022d44861f46a4cda12af74d44057540771b7bab`.
