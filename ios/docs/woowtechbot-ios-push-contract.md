# iOS push integration target and three-deployment acceptance

Status on 2026-11-27: client implementation, Firebase iOS registration and a
signed development package with the dedicated APNs entitlement are prepared.
This is a proposed backend contract; no PaaS/HA/Podman deployment is claimed to
implement it until authenticated discovery and physical delivery are verified.

## Deployment scope

| Deployment | Current test origin | Identity |
| --- | --- | --- |
| PaaS test lab43 | https://paas-cs-671d61b1-e823b18c.woowtech.io | New dedicated iOS pairing required |
| Home Assistant add-on | https://woowtechbot-ha.woowtech.io | Separate new iOS pairing required |
| Podman | https://woowtechbot-openclaw.woowtech.io | Separate new iOS pairing required |

Each service receives its own UUID, website data store and server session. The
same installed app can connect all three. Existing Android pairings must remain
untouched. Public homepage/pair-page HTTP 200 is an entry check, not pairing or
notification acceptance. Authenticated discovery is intentionally unavailable
without that service's cookie.

## Discovery and registration

HTTPS only for remote push. The original same-origin website handles pairing.
Native requests capture cookies from that exact WKWebsiteDataStore, require
matching cookies on the discovery/device paths, reject redirects, limit response
size to 64 KiB and never log credentials. The app does not follow server-supplied
routes. LAN HTTP remains available for explicit website use, without remote push.

`GET /api/auth/session` must identify a cookie-authenticated client session:

```json
{
  "kind": "session", "via": "cookie", "cookieOnly": true,
  "id": "dedicated-ios-session", "environmentId": "deployment-environment",
  "scopes": ["client"], "capabilities": {"woowtechIOSPush": 1},
  "woowtechIOSPush": {
    "devicePath": "/api/woowtech/ios-push/device", "payloadVersion": "1",
    "auth": "cookie", "acceptsCookieOnly": true, "enabled": true, "ready": true
  }
}
```

The server may retain the existing Android capability independently. iOS `ready`
must mean the dedicated iOS registration and APNs alert sender are configured,
not merely that the Android data-only sender is running.

`PUT /api/woowtech/ios-push/device` uses the captured cookie, matching `Origin`,
and `X-Woowtech-Session-Id`. JSON is `{v:1, platform:"fcm", serviceId:<lowercase UUID>,
token:<opaque FCM registration token>, locale:"zh-TW"|"en"}`. `locale` is the app's
interface language as the push relay names it (a Chinese interface is `zh-TW`,
anything else `en`); the app registers again when it changes. Build 294 sends no
`locale`: treat a missing one as `zh-TW`. The backend must bind the authenticated
identity, validate the service UUID, support idempotent token replacement, and
reject stale/mismatched session headers. Its successful response has exactly:

```json
{"v":1,"serviceId":"service-uuid","registrationId":"registration-uuid","state":"registered","registered":true}
```

The two UUID placeholders above must be actual canonical lowercase UUIDs.
Pending/non-200/extra fields are never accepted as a successful registration.

`GET /api/woowtech/ios-push/device` uses the same authenticated cookie/session
headers and returns this session's current registration with the same five
fields. A notification tap requires a fresh `registered` response matching its
saved service UUID. An `absent`/`pending` response must not authorize navigation.
This also prevents a concurrent foreground registration refresh from treating
its local pending ledger as the final server state.

`DELETE /api/woowtech/ios-push/device?serviceId=<same UUID>` uses the original
cookie/session identity. Successful idempotent cleanup returns exactly:

```json
{"v":1,"serviceId":null,"registrationId":null,"state":"absent","registered":false}
```

Logout/session revocation must revoke its push registration server-side, including
when a device lost its local cookie. Missing discovery or network errors are not
authorization to delete another identity's registration. Backend responses and
logs must not echo tokens, cookies or chat contents.

Registration and discovery failures are scoped to the affected service; they
must not prevent another deployment from registering. The client preserves each
service's retry/cleanup status independently and does not count a partial
registration batch as complete.

## Sending: through the WoowTech push relay, as woowtech smart does

Owner decisions on 2026-11-27: iOS push goes through Firebase (FCM to APNs), and
it follows the push design of woowtech aiot, smart and platform. The backends
therefore do not call FCM for iOS registrations: like the smart daemon, they send
each notification to the WoowTech push relay, which alone holds the FCM sending
rights, limits every token (10 a minute, 500 a day) and writes the text. Android
registrations keep the backends' existing FCM sender for now.

`POST https://botpush.woowtech.io/api/bot/v1/notify` (relay `WOOWTECH/woowtech-push-relay`,
profile `bot`, branch `bot-mode`; contract fixtures
`functions/test/fixtures/bot-notify-v1.fixtures.json`) with exactly:

```json
{"token":"<FCM token>","locale":"zh-TW","reason":"finished",
 "target":{"serviceId":"<lowercase UUID>","botId":"<id>","threadId":"<id>","eventId":"<lowercase UUID>"}}
```

`locale` is the registration's (`zh-TW` when it has none). `reason` is `finished`,
`permission`, `attention`, or `failed` for a run that ended in an error (owner
2026-11-27, as Android). `botId` and `threadId` are the website's IDs within
`[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}`; anything else is refused with 400 and the
offending field. Answers: 201 sent; 410 `token_invalid` (delete that registration);
429 rate limited (drop it); 503 or a network error or no answer within 10 s (retry
once after 2–4 s); 502 `upstream_auth` (the APNs key or the relay's FCM rights,
keep the registration, do not retry); 400 or 413 (a backend bug, do not retry).

The relay sends a standard APNs alert through FCM with Android's fixed sentences:
title `WOOWTECH Bot`; body `機器人已完成，請開啟查看。` / `A bot has finished. Open to
review.` for `finished`, `機器人需要您的注意，請開啟查看。` / `A bot needs your attention.
Open to review.` for `permission` and `attention`, and `機器人未能完成，請開啟查看。` / `A bot
couldn't finish. Open to review.` for `failed`. Default sound, `apns-push-type:
alert`, priority 10, a one-hour expiration, one notification per conversation
(`apns-collapse-id`), no `mutable-content`, and no chat contents: nothing of a
conversation passes through Apple or Google. FCM data contains one `woowtechbot`
string: JSON of exactly `v`, `serviceId`, `botId`, `threadId`, `eventId`, `reason`,
with `v` the string `"1"`. No URL or action command.

Firebase project `woowtech-assistant` (795023111689), iOS app
`1:795023111689:ios:289442214db27c7f442ad8`, APNs topic `io.woowtech.assistant.bot`,
Apple team `W4UWZ8NP2P`: a pair of APNs keys limited to this topic (sandbox and
production), as smart has, uploaded to this Firebase iOS app. Never a key of
Smart/Apporo.

The system can display a background alert before the app validates it. Therefore
server-side identity revocation and generic notification content are essential.
The app validates an explicit tap against the current authenticated registration
and only opens the saved service origin with bot/thread query parameters. It does
not automatically execute approvals, sign-in or tools. A notification service
extension and silent background processing are not required for this alert path;
an extension that writes the text on the phone (for example with the bot's name)
would be a later app change, announced to the backends before they set
`mutable-content`.

## Required acceptance per deployment

1. Dedicated iOS pairing; cancelled/wrong-origin/expired pairing; profile isolation.
2. Capability discovery and explicit permission allow/deny; server registration ACK.
3. Foreground, background and terminated-process visible receipt on physical iPad;
   record the exact event and distinguish termination from user force-quit.
4. Explicit tap opens the correct service, bot and thread. Repeat/stale/unknown
   events and disabled/retired profiles must not reopen another identity.
5. Natural model-completion event, permission-needed event, offline/reconnect,
   token refresh, logout, fresh login and server-side revocation.
6. Real camera QR decoding, attachment upload, link download, actual Files save
   and share completion, with content integrity where applicable.

Local fixture/core tests and simulator notification injection are separate evidence.
All three deployment columns must pass physical acceptance before a release claim.
