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

The existing system notification delegate owns both local-task and Bot callbacks.
Bot payloads use `userInfo["woowtechbot"]`, either the six-string dictionary or
its bounded JSON string (FCM data values are strings). Opening requires consent,
the current enabled profile, a fresh authenticated discovery, and an acknowledged
registration for that exact profile/session identity. This never approves actions.

The user selected the existing Firebase project `woowtech-assistant` and a separate
iOS app. Firebase app `1:795023111689:ios:289442214db27c7f442ad8` was created for
`io.woowtech.assistant.bot`. Firebase 13.2.0 Core/Messaging dependencies are restricted
to the Bot spec. Swizzling, automatic token generation and Analytics collection are
disabled. The client initializes after explicit push consent; APNs tokens are mapped
through the existing UIApplicationDelegate. Denial/off unregisters APNs and deletes
the FCM token. No token, cookie or session credential is stored in the push ledger.
The SDK's new installation-ID registration mode is explicitly disabled because
this integration uses the existing FCM token wire contract. Firebase 13.2 still
supports that mode, with deprecation warnings for `token()`/`deleteToken()`; a
future FID migration requires coordinated sender and registration-contract changes.

The encrypted ledger records identity and token digests **before** PUT, retaining
ambiguous registrations on network errors. A validated server ACK is needed for
the registered status. Disable/logout attempts DELETE with the original profile;
failed cleanup is displayed and retained. No new identity may acknowledge an old
identity's revocation. Service cookies are never shared with the native assistant.

Android's `woowtechAndroidPush` capability is deliberately insufficient. The iOS
client requires the proposed `woowtechIOSPush` contract documented in
[woowtechbot-ios-push-contract.md](woowtechbot-ios-push-contract.md). That document
is the integration target, **not evidence that the three deployed backends already
implement it**. Candidate 13 has an explicit push-enabled development profile.
APNs credentials in Firebase, authenticated three-deployment registration,
and physical delivery remain pending.
Existing local assistant notification preferences stay independent.

## Reproducible validation

Generate inside this worktree's iOS directory (or copy its Configuration files
when generating into a separate output directory):

```sh
python3 ios/scripts/bot_firebase_app.py --gcloud /path/to/gcloud \
  --output ios/Configuration/Private/GoogleService-Info.plist
xcodegen generate --spec ios/project-woowtechbot.yml --project ios
mkdir -p ios/WoowAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
cp ios/Configuration/BotFirebase-Package.resolved \
  ios/WoowAssistant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
xcodebuild -project ios/WoowAssistant.xcodeproj -scheme WoowAssistant \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /path/to/isolated/DerivedData -jobs 1 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=W4UWZ8NP2P PROVISIONING_PROFILE_SPECIFIER= \
  -onlyUsePackageVersionsFromResolvedFile build
```

Firebase management uses the selected authenticated gcloud account. When the host
keeps assistant credentials in an isolated configuration, set `CLOUDSDK_CONFIG` to
that existing directory. The script supplies the exact quota project, validates
project number/bundle/app IDs, and writes a local ignored client plist without
printing its API key. `--apply` is only needed for first-time app creation.

The entitlement is development APNs for this non-store variant. Device builds
need an explicit push-enabled provisioning profile; the prior wildcard profile
used by candidate 7 cannot provide APNs. Do not change to production solely to
make a local signing check pass.

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

The previous simulator candidate (before Firebase integration) is candidate 7,
app build 294, executable
SHA256 `6e3833d46f75080cb6e424fb20abf6df297227e6c50a12e827ad045105d93efa`.
Its source hashes are retained in those runs' request/result snapshots;
`candidate.json` now points to the latest candidate. Test runs verify the
source file set, individual hashes, installed executable and UI driver.

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

At the candidate 7 checkpoint, the physical iPad was unavailable to Xcode. Real camera decoding,
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

## Push preparation on 2026-11-27

Candidate 13 compiles for both the arm64 simulator and physical iOS from the
same recorded source hashes. Firebase client configuration is bundled only in
the Bot variant. The physical app has a valid Apple Development signature, an
explicit `W4UWZ8NP2P.io.woowtech.assistant.bot` profile, development APNs
entitlements, and the target iPad in its provisioned-device list.

`WOOW-Assistant-Bot-294-push-candidate13-development.ipa` is the new local test
package (SHA256 `b86b6ca77ad9977d5bf402ff814fe2663b7423b611a0203f27592166def4789b`).
It has not been installed or accepted on the disconnected iPad. It supersedes
the earlier candidate 7 package for subsequent push testing. This is not a
TestFlight archive or an upload of standard build 293.

Thirteen Foundation tests pass: the five service/profile/target tests plus
eight push-discovery, strict-ACK, identity-binding and pending-ledger tests.
The tested core source hashes still match this candidate.

UI testing exposed an asynchronous toggle setter that did not save the user's
selection. The setter now saves synchronously, then requests system permission.
A real simulator system prompt was displayed and accepted on candidate 11.
Cookie reads now share each service's retained website data store and have a
bounded wait. Candidate 12 verified that a failed read leaves a retry status
instead of indefinite checking; retry is not counted as authenticated discovery.
The latest registration loop also continues with the other deployments when
one request fails, and checks profile freshness before acknowledging success.

Remaining external prerequisites: dedicated iOS pairing for all three services,
authenticated access to the backend source/deployments, this bundle's APNs
credentials in Firebase, and a connected/unlocked/trusted physical iPad.
The backend repository currently redirects command-line access to Cloudflare
Access login. The proposed iOS contract has not been verified on any deployment.

## Direct UI alignment (Android woow.22 / preview06) on 2026-11-27

The Direct palette (midnight `#121212`, daylight `#fcfcfc`, accent `#7fc0ff` /
`#0b69cc`), the four circular history controls, the search card, the shortcut
menu and a native services/notifications presentation are compiled only with
`WOOWTECHBOT`. The remote website keeps its own header and themes. When a page
has the app's sidebar slot (`[data-look="app"] [data-sidebar-top-slot]`), an
isolated `WKContentWorld.defaultClient` script adds two circular controls whose
links are `woowtech-ui://services` and `woowtech-ui://notifications`. The
navigation delegate accepts exactly those two addresses, only from a link the
user activated in the main frame of the saved origin (`BotWorkspaceAction`,
two unit tests); there is no JavaScript bridge, and the script reads no cookie,
storage or page content. While the controls are installed the native toolbar is
hidden; sign-in pages and pages without the slot keep the native toolbar.
The injection's own completion value is not delivered by `evaluateJavaScript` on
the iOS 27 simulator (`Optional(())`), so readiness is probed separately with
`callAsyncJavaScript`. The services sheet gained the current service's tools
(local assistant, downloads, pairing, share address) to replace the hidden menu.

Verified on candidate 18 (simulator iPhone, light and dark) and on the physical
iPad (development-signed build, explicit push profile): history, services sheet,
sign-in page with native toolbar, signed-in fixture page with injected controls and
hidden toolbar, services sheet from the injected button, notifications sheet,
downloads and local-assistant return paths (iPad: services and notifications
buttons). The fixture server now serves the sidebar structure only after
sign-in, as the real site does. The earlier push UI test failure at step 42
was the UI driver's `toggle` step not registering on this simulator, not the app:
a coordinate tap switches the push toggle, saves it and shows "Push is off".
Not verified: real woowtechbot pages, real camera QR, authenticated pairing,
push delivery, the Android sub-page popovers (still in progress on Android).

## Native sub-screens aligned to woowtechbot (Android `feat/woow-native-subpages-alignment`) on 2026-11-27

The Android line measured the real woowtechbot website (phone Midnight tokens, popover and sheet geometry) and rebuilt its native
screens from one component family (`BotUiPopovers.kt`, `BotUiSheet.kt`, `components/Dialog.kt`, `BotUiAvatar.kt`). The iOS Bot variant
follows the same numbers, compiled only with `WOOWTECHBOT`:

| Android | iOS (`ios/Sources/App`) |
| --- | --- |
| `WoowDark/LightColors` (page `#141414`, card `#242426`, control `#2c2c2e`, hairline `#3a3a3c`, popover radius 22) | `MikaVisualPalette(.app)`; phone Midnight only on iPhone, the desktop set (`#121212` / `#1f1f1f`) on iPad, as the website does at 768 px |
| `WoowSheetDark/LightColors` (`#121212`, cards `#1f1f1f`, white cards in Daylight) | `MikaVisualPalette(look: .sheet)` for the bottom sheets only; Mika's own settings pages keep the app look, as on Android |
| `hair.copy(alpha = .5f)` replaces alpha | `hair50` (half of the opaque Midnight hairline, ink at 50 % on Daylight) |
| popover (anchor box, 8 gap, 8 from the edge, min 200/220/240, max min(screen − 24, 320), `pop-in` 0.2 s) | `BotUIComponents.swift` `BotPopoverLayer` + `BotPopoverLayout`; anchors are window frames, the layer is above the screen it serves |
| sheet (grabber 32 × 4, 44 header, 16 / 6 / 16 / 24 body, cards 12) | `BotSheetScaffold` inside the system sheet (rise, 16 pt corners, drag to dismiss) |
| `MikaDialog` (menu colour, 20/26 title, 14.5/23 body, 6 % / 10 % ink pills, red destructive) | `BotDialogHost` / `BotDialogSurface` / `BotDialogButton`; also used for notices and the external-link and pairing confirmations |
| `BotUiAvatar` (32-unit art, 11 colours, face auto / white / black, legacy six mapped) | `BotAvatarView.swift` draws the same paths (`BotSVGPath`); `BotConversationAvatar.palette` 1 / 2 with legacy decoding (unit test) |

Screens and behaviours aligned: history (four round controls, title row with "Back to conversation", rows without separators, current
unsaved row, running → pinned → latest order, time format, row "…" popover, bottom bar with the shortcuts popover and the search
pill, delete dialog), gear popover (Settings, About), plus popover (New chat, Add woowtechbot service), switch assistant / service
sheet (local assistant row, services card with check and "…", add dialog with the same validation message), service manage sheet
(scan QR, reload, share, disconnect, log out, remove) with the shared confirmation, Bot notifications sheet (switch enabled rule,
retry row, system settings row, one row per enabled service), chat header (round back, name capsule that opens the name page, "…"
popover with name and icon / new chat / find / files), name and icon page (round ✓ ✕, 68 pt tile with pencil, inline name,
robot / upload tabs, three styles, eleven colours, face), Find and Files pages, chat bubbles (user `#5A5A5A` / `#1C1C1C`, 18 pt, at most
80 % wide; assistant full width, 20 / 20 / 20 / 6), composer (the plus is its own 48 pt circle, mic only when empty, send only when
there is something to send, stop while a task runs).

Deliberate differences (platform): SF Symbols instead of Android's stroke icons; the shortcuts popover lists the tools iOS has
(Memory & skills, MCP servers, Browser, Files; not scheduled tasks, connect a computer, background screens); the manage sheet adds
Downloads (iOS has no per-download document picker); the notification sheet speaks APNs and opens iOS notification settings; the
service screen's fallback bar keeps a Back chevron (there is no system back); pairing also accepts a pasted link; the Files page keeps
Save to Files and Share for generated files; the composer keeps iOS's separate hold-to-talk mic button instead of Android's
hold-anywhere placeholder.

Verified on candidate 34 (simulator iPhone, dark and light, English and Traditional Chinese, accessibility size 5 for the history,
popover and services sheet): popovers, dialogs, sheets, chat header and menu, name and icon page, find and files pages, chat bubbles and
composer (Debug build with the fake model), service screen fallback bar, injected controls, manage sheet, cancel and confirm logout,
relogin, removal, a second service on the same origin staying independent, add dialog validation. Not verified: real woowtechbot pages
behind a pairing, camera QR scanning, push delivery.
