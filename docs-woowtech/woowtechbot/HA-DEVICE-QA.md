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
