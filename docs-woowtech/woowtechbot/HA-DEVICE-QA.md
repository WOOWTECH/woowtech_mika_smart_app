# HA native FCM QA — 2026-11-26

Device: POCO C85, io.woowtech.agent 3820 normal release, diagnostics=false. Existing lab43/lab53 and Podman profiles preserved.

Independent profile android-qa-ha, origin https://woowtechbot-ha.woowtech.io. One-time client pairing completed via encrypted handoff and native UI input; no QR camera claim. No credentials recorded.

HA QA bot: e6763931-993b-4e56-80d9-e87705f2d929 (android-qa-ha-20261126); agreed seed: 5c288d5b-ade1-40ca-ab16-9f7a2477762b.

HA and PaaS independently reported matching registered/relay ACK baseline:
- serviceId: 6a0f26fa-c49f-4350-983b-1f52592b72a8
- sessionId: 2119d0ec-d79d-45b1-a5b7-eb338a4f3483
- registrationId: 1957f5aa-c83f-4fa9-996d-c7dd41318f80
- revision: 1; relay live; no events at baseline.

Phone native notification UI shows registration confirmed, delivery not yet verified. HA QA bot and composer are visible. Single-thread menu has no multi-thread picker; exact seed metadata requested from HA. No model request made.

Home background ready explicitly sent to PaaS after topResumedActivity became launcher. Exactly one new manual attention fixture authorized. This is not a cold-process test or natural model completion. Receipt and origin/bot navigation passed as below; exact seed awaits post-tap server metadata.

## First actual HA background receipt

Manual attention event f7ff2583-b8f1-4d08-ae15-4dc56e172ee8. HA send 13:05:19.742Z, ACK 13:05:22.027Z, HTTP200; PaaS independently reported durable sent at 13:06:05Z. These are server-side reports, not phone arrival timestamps.

Phone dumpsys active NotificationRecord count=1 for exact tag:
`6a0f26fa-c49f-4350-983b-1f52592b72a8|e6763931-993b-4e56-80d9-e87705f2d929|5c288d5b-ade1-40ca-ab16-9f7a2477762b|f7ff2583-b8f1-4d08-ae15-4dc56e172ee8`.

Visible generic attention body was inspected via filtered UI metadata. First tap expanded notification group; second body tap opened BotServiceActivity. Screenshot confirms exact HA origin, QA bot and composer/initial greeting. No thread was manually switched. This passes actual background receipt and service/bot navigation. Single thread has no picker; post-tap server metadata requested before marking precise seed verified. Further fixtures HOLD.

Evidence: [native registration status](evidence/20261126-ha-fcm/registered.png), [after actual notification body tap](evidence/20261126-ha-fcm/after-notification-tap.png). No notification-shade screenshots saved; temporary notification XML removed. No model call, cold-process test, offline-delivery test, or QR-camera decode in this run.

## Post-tap server corroboration

HA reported readonly verification at 13:07:24Z: exact QA bot/name, bot.threadId=5c288d5b-ade1-40ca-ab16-9f7a2477762b, seed present in tasks and messages endpoint 200, original phone client live and same registration registered. This corroborates the phone notification tag and visible QA destination; no separate phone-internal selected-thread ID was observed because this is a single-thread bot without picker. Background receipt and target navigation accepted with this explicit evidence limit. One artificial event only; further fixtures HOLD.

## Cold process receipt (3820)

Home then `cmd activity stop-app io.woowtech.agent` (not force-stop). At13:55:46.411832Z pidof empty and package stopped=false. One-second PID monitoring started13:56:01.788438Z absent; first PID9068 observed at Mac13:57:27.891779Z. Host/device clock differences and poll interval apply. Device AMS at21:57:28.048 local (13:57:28.048Z) records Start proc9068 for FirebaseInstanceIdReceiver, caller com.google.android.gms. This falls within HA send13:57:27.869Z and ACK13:57:28.776Z; no manual launch before receipt.

New manual attention event810540c3-0559-4aa9-84bf-29a97050d29f matched complete active tag (same HA service/bot/seed). Actual notification body tap opened BotServiceActivity and correct HA origin/QA bot/composer. [Cold receipt tap evidence](evidence/20261126-ha-fcm/cold-after-tap.png). PaaS separately reported durable sent. HA post-tap seed metadata requested. This tests process absent while stopped=false, not force-stop, low-memory reclaim, offline delivery or natural completion. No model call in this step.

## HA natural model completion — 2026-11-26

Normal 3820 package remained installed throughout this test. HA reported normal message API sendId `a8ba5bb6-a371-43b9-a5a5-fbd0624c4ac6`, provider success at 14:02:12.705Z, and native done-path event `25a3d373-9484-4da6-a22b-6fb3f61efae9`. PaaS independently confirmed durable sent state and expected finished payload match at 14:04:08Z. These are server-side reports, separate from phone evidence.

Phone active notification tag matched HA service, bot, seed and event. The completed notification was visible; first tap expanded its group, second tapped the actual body. BotServiceActivity then displayed the exact HA origin, QA bot android-qa-ha-20261126, composer and assistant response `android-qa-ha-natural-a8ba5bb6`. See [phone screenshot](evidence/20261126-ha-fcm/natural-after-tap.png). No Android-side model request, notification injection, update or reinstall occurred. Single-thread UI has no picker; no independent phone internal selected-thread-ID claim. This is Home-background natural model completion, separately from the earlier manual cold-process fixture.

HA final readonly corroboration at 2026-11-26T14:07:59.029Z: bot.threadId equals seed, seed task exists and thread API responds; phone client session remains live, matching registration remains registered/revision1, outbox jobs=0. HA reported no further model or fixture requests. Evidence capture time for natural screenshot: 14:06:39.106256Z (not an instrumented tap timestamp). All further fixtures remain on hold.

## woow.21 in-app update verification

Published stable latest v0.1.37-woow.21 at 2026-11-26T14:45:44Z from main 537c41fd473e7fcc1d75cb7a99a1b69c522feaa3 after successful main CI and brand release jobs. Package io.woowtech.agent / versionCode3821; original signing certificate matches. Public arm64 APK SHA256 a93da5d6a45ef34d853e4a98be233375053201a42eb4761f71eb79f421a0eca4. Firebase client resources and project value checked.

Phone About → Check update detected21, downloaded through the App, and opened the Android update confirmation. After confirming Update, Play Protect requested a scan; scan returned harmful-app block with generic potentially harmful wording. Details gave no specific component/category. No bypass, protection disable, ADB install or uninstall performed. Installed package remained3820 and firstInstallTime2026-11-09 13:12:33. Manifest permissions unchanged compared with the tested3820 APK; this does not establish why Google classified it.

Update discovery/download/system installer launch PASS; overwrite installation BLOCKED by Play Protect, not passed. Screenshots: [update](evidence/20261126-ha-fcm/update21-dialog.png), [download complete](evidence/20261126-ha-fcm/update21-download-ready.png), [system confirmation](evidence/20261126-ha-fcm/update21-install-confirm.png), [scan block](evidence/20261126-ha-fcm/update21-block-details.png). Prior HA tests remain3820 evidence.
