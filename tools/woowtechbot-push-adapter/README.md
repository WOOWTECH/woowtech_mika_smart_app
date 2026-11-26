# WOOWTECH bot own-relay adapter

Self-contained Node.js ESM shim, Node 20+, zero installed dependencies. The relay authenticates and authorizes installation requests, tracks registration/deduplication state, and sends data-only FCM messages through an injected sender. Android validates and gates each event before rendering a local notification; all display text and localization belong to the Android client. No listener, Firebase initialization, environment/credential reads, deployment, or real sends occur on import or test. All changes are confined to this directory.

Run: `node --test tools/woowtechbot-push-adapter/adapter.test.mjs` from the project root.

## Source evidence and compatibility boundary

Inspected WOOWTECH/woowtech-push-relay `smart-mode` at commit `dff78a18d6bffc6a37c2e791e366fc96bc87656d` through read-only GitHub API calls:

- `functions/webapp.js`: smart profile exposes **POST /api/smart/v1/notify**, with an edge-key guard, 1024-byte limit; no installation registration routes.
- `functions/smart-validate.js`: closed `{token,locale,reason,target}` with Smart-specific server/workspace/agent/terminal IDs. It does NOT accept the assistant target schema.
- `functions/smart-payload.js`: upstream uses notification + routing data. This assistant shim intentionally uses DATA-ONLY with high Android priority and a 10-minute TTL so client validation cannot be bypassed by background OS display.
- `functions/smart-notify.js` and tests: injected messaging boundary, conservative token invalidation, no reflected provider messages. Adapted here; sender-project mismatch deliberately preserves registration and pauses instead of revoking.
- `functions/smart-messages.js` was inspected for upstream context. No text table is shipped or used by this data-only adapter.

See [UPSTREAM-NOTICE.md](UPSTREAM-NOTICE.md) for source provenance and adaptation details, and [UPSTREAM-LICENSE.md](UPSTREAM-LICENSE.md) for the retained upstream Apache 2.0 license.

Also inspected `/tmp/woowtechbot-mobile-ui-research/source/server/phone-push.ts`, its tests and `docs/phone-push.md`. The bot expects the three installation routes below, bearer auth and errors `push_device_unknown`, `push_device_unregistered`, `push_unavailable`. Its existing send body has caller-supplied title/name fields and lacks service/event IDs. **This shim matches route names and relevant error semantics, but intentionally requires a new closed body. It is not a drop-in replacement for the unchanged bot or Smart endpoint.** The shared phone-protocol implementation was absent from the research checkout; route/error evidence comes from the bot implementation/tests/docs.

## HTTP contract implemented by the shim

All routes POST, `Authorization: Bearer <installation credential>`, JSON, maximum 4096 bytes at the HTTP mount. Credential verification is mandatory and injected; regex syntax alone never authenticates. These routes must be mounted on an own relay/control-plane origin. They are not claimed to exist upstream or in production.

| Route | Exact required body fields |
| --- | --- |
| `/v1/installations/self/push/register` | `v:1, platform:"fcm", token, serviceId` |
| `/v1/installations/self/push/unregister` | `v:1, platform:"fcm", token, serviceId` |
| `/v1/installations/self/push/send` | `v:1, token, locale, reason, target:{serviceId,botId,threadId,eventId}` |

No optional fields. Reject unknown fields at both levels, caller text, names, URLs, pairing, collapseId, legacy notification objects, arbitrary data, APNs and other versions. Locale is `en` or `zh-TW` (retained for request compatibility only; not transmitted or used for display by the relay); reason is `finished`, `permission`, or `attention`. Each target ID must be an opaque local ID matching `[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}`. Never place human text into IDs. Syntax does not establish ownership: backend authorization and local Android binding checks are mandatory. FCM tokens follow upstream's 20–512 URL-safe/colon-character format with at least one colon.

`serviceId` scopes registration to an installation's authorized service; it is an intentional addition to the bot's original registration body. Registration is idempotent. Unregister is idempotent and deletes only that installation/service/token binding. A token can have multiple explicitly registered service bindings; clients must unregister every removed binding. Registering does not contact FCM or prove a token is deliverable.

Response body never contains tokens, credentials, IDs or provider messages:

| Status | Body / handling |
| --- | --- |
| 200 | `{ok:true}` registration/removal; `{ok:true,duplicate:true}` suppressed duplicate |
| 201 | `{ok:true}` Firebase accepted message; not proof of phone delivery |
| 400 | `{error:"invalid_request"}`; fix caller |
| 401 / 403 | `unauthorized` / `forbidden`; stop and resolve installation/service permissions |
| 404 | `push_device_unknown` for unregistered binding; bot may register then retry once; `not_found` for unknown path |
| 405 | `method_not_allowed` in pure handler |
| 410 | `push_device_unregistered`; delete stale device/token |
| 429 | `rate_limited`, header `retry-after: 60`; bounded retry/backoff |
| 502 | `push_unavailable`; ambiguous payload/auth or wrong Firebase project: pause, keep token, operator repair |
| 503 | `push_unavailable` when sender absent; `upstream_unavailable` on transient/provider/storage/auth-verifier failure |

Fastify itself handles malformed JSON, media type, oversized bodies and unsupported methods before this handler. Configure redacted generic error responses and disable request/body/header/query logging at the host and proxy. The pure handler accepts already-parsed JSON and does not enforce the transport body limit. No logging is performed by these modules.

## Data-only Android contract

The client platform designation is `woowtech-direct`; transport registration uses `platform:"fcm"`. This label is not an extra FCM field. Own assistant Firebase project and Android Firebase configuration are pending; do not reuse the Smart or AIoT project implicitly.

FCM `data` contains **exactly six string fields**, no locale or platform:

```json
{
  "v": "1",
  "serviceId": "service_demo",
  "botId": "bot_demo",
  "threadId": "thread_demo",
  "eventId": "event_demo_0001",
  "reason": "finished"
}
```

`fixture.json` is the corresponding full fake send request. `buildMessage(fixture)` produces exactly this Firebase Admin SDK message shape:

```js
{
  token: "fake-fcm-token:fixture_only_000000000000000000",
  data: {
    v: "1", serviceId: "service_demo", botId: "bot_demo",
    threadId: "thread_demo", eventId: "event_demo_0001", reason: "finished"
  },
  android: { priority: "high", ttl: 600000 }
}
```

**DATA-ONLY is mandatory. Neither root `notification` nor `android.notification` may be present.** The FCM payload has no text, channel, tag, visibility, click-action, URL, intent, or locale fields. The relay must never enable background OS auto-display, which would bypass stale/unknown service and account checks. `FirebaseMessagingService` owns handling in foreground and background; it intentionally ignores `message.notification`.

Android must validate the exact schema/version/reason, resolve the active local account/service binding, reject stale/unknown/unpaired bindings, and deduplicate the service/bot/thread/event identity **before displaying any local notification**. The client selects fixed localized generic text from its own resources and uses its own channel/tag/visibility settings. Proposed local channels remain `woowtechbot_results` for finished and `woowtechbot_attention` for permission/attention; `CHANNELS` is reference metadata used for reason validation, never emitted by `buildMessage`. Android owns final local channel wiring. On tap, recheck binding and authenticated-fetch the event/thread; never execute actions from push data. High delivery priority is a transport setting, not a guarantee of delivery or permission to bypass local gates.

The tests assert the complete data-only payload for every accepted locale/reason and through the injected sender. They prohibit both notification objects. `locale` remains a required, validated HTTP request field for compatibility with this adapter contract; it is omitted from FCM and has no effect on the generated message. Android chooses the display language locally.

## Integration seams (not wired by this change)

1. Relay/control plane: import `createAdapter` and `mountRoutes` into a dedicated assistant profile/server. Do not simply enable Smart's current route: it rejects these targets and only knows an edge key, not installations. Add the new paths/body limit to any Worker/proxy allowlist explicitly; no proxy or deployment code is modified here.
2. Supply `verifyInstallation(bearer) -> Promise<{installationId}|null>` using the actual credential verifier/revocation database. Unknown/expired/revoked credentials return null; backend failures throw and yield 503. No trust in user-supplied installation IDs. `authorize(principal,{operation,serviceId,target?}) -> Promise<boolean>` must check service ownership for all operations and bot/thread/event relationship for sends. Callback errors fail closed. Android's local service binding check does not replace this backend check.
3. Supply `state` with async `register(key)`, `unregister(key)`, `has(key)` and `run(eventKey,work)`. Registration keys hash installation/service/token. `run` must atomically share an in-flight result, retain successful dedup claims for at least the retry horizon (default memory TTL 10 minutes), and release failures. Event keys hash that registration key plus bot/thread/event, intentionally independent of locale/reason. No raw tokens are persisted by the memory reference. Production needs durable registration bindings, shared bounded dedup claims/leases, quotas and revocation handling. Shared run must return success after a successful send even if its post-send bookkeeping fails, and surface that failure via safe operational metrics, rather than invite blind retries. Crash between Firebase acceptance and dedup commit is inherently ambiguous: this is not exactly-once delivery. Android event dedup is still needed.
4. Only once a user-owned assistant Firebase project is provisioned: inject `sender: message => getMessaging(assistantApp).send(message)` from an explicitly configured named Firebase Admin app. The module does not import/init Firebase or locate credentials. Omit sender to get `503 push_unavailable`. Tests always use fake senders. Project mismatch preserves tokens for configuration repair. Configure provider timeouts/transport and safe metrics at that boundary; the pure shim does not forcibly cancel Firebase sends.
5. Bot: preserve `PhonePush.offer` audience (`reaches`), feature flag, live-stream suppression, per-phone opt-in and coalescing/rate limits. At frame capture, call `fromBotFrame(frame,{token,serviceId,locale,eventId})` instead of creating name-based `phonePushNotification`. This projects only IDs and maps done→finished, approval→permission, question/sign-in→attention. Assign a durable event ID at event creation and keep it on retries; if using a sequence, namespace it with a persisted stream epoch. Sequence alone restarts and is not a valid event identity. Store serviceId/locale alongside the phone binding. Use new registration/removal bodies with serviceId. Remove pairing/collapseId/name/title fields from relay sends. These are concrete required edits in the bot, not changes made here.
6. `createRelayClient({origin,credential:()=>installationCredential,fetchImpl?})` supplies `(operation,body)` with HTTPS-origin-only URLs, header-only auth, no redirects, 10s timeout and the bot's `{status,code,retryAfterMs}` result shape. Origin and credentials must come from the installation's verified own-relay configuration. It does not automatically choose a deployed origin. Existing PhonePush retry policy can consume results; teach it that 403 is an authorization pause and keep its unknown-device one-shot re-registration. Token refresh should register the new binding before removing the old; failed unregister needs persistent retry/reconciliation.

`createMemoryState()` is an explicit development/single-process reference (bounded to 10000 registrations and dedup entries), not a production database or distributed limiter. There is no durable outbox, quota engine or token-registration proof here. A production registration endpoint must be reachable only through trusted paired-device flows on the bot, with rate limits and token-refresh/unpair reconciliation. Do not expose installation credentials to Android.

Remaining dependencies: actual installation verifier/ownership records; durable binding/dedup store and quotas; bot changes above; assistant Firebase project, app configuration and sender authorization; Android channels/parser/navigation implementation; relay profile/proxy deployment and device tests. None have been provisioned, registered, deployed or sent by this implementation.
