# Deployment record

As of 2026-11-11, the Apporo OAuth provider is installed on production Odoo at www.apporo.ai and the independent `apporo-assistant-relay` Worker is live at https://assistant-relay.apporo.ai/. The custom domain belongs to the Cloudflare account that owns apporo.ai. The Worker has its own `OWNER_KEY`, `RELAY` and `AUTH` Durable Objects; none of the WOOWTECH relay's credentials or storage are shared. The current Worker version is `cccd2d44-9366-4bed-8af5-c9778b1d8e20` (first deployment: `1090e28b-8c8f-44c2-b68c-7584e71e02a1`).

The Apporo .8 signed candidate was installed over .7 on a physical Android 15 phone. Its package identity, signing certificate, model settings and chat draft survived the upgrade. Odoo consent, browser callback, account page, one-use pairing, phone WebSocket, personal CLI, MCP and a model-driven remote task were exercised against the live Worker. See [the acceptance record](../../docs-apporo/RELAY-ACCEPTANCE-20261111.md). This is not yet a public Apporo APK release.

## Production notes

- Before Odoo installation, a verified custom-format database backup was made. Two post-install `HttpCase` tests passed in an isolated database. The production addon lives in the `apun-odoo` deployment in the `apun` Kubernetes namespace.
- Chromium initially blocked the consent POST's redirect because the Odoo page's `form-action 'self'` CSP did not include the Worker callback origin. The Odoo controller now permits only `https://assistant-relay.apporo.ai` in addition to `'self'`; production was patched and restarted, and a fresh browser authorization completed through `/auth/callback` to `/account`.
- The Cloudflare browser-integrity check rejected the downloadable CLI's default `Python-urllib` User-Agent with HTTP 403. The Apporo relay CLI now sends `User-Agent: apporo-relay-cli/<version>`. A regression test checks this header. The corrected public download was byte-for-byte checked against source and used to connect to the physical phone.
- A private phone access token is required for personal MCP and CLI calls. A pairing code, the website session and the phone's gateway device token are different credentials. Keep tokens out of reports, command output and source control.
- The gateway's remote wake/unlock switch is off by default. With it off, MCP exposes seven task tools; when temporarily enabled on the physical phone it exposed the same ten tool names as the current WOOWTECH relay. It was turned off again after that check.

## Google Play edition (prepared 2026-11-13, not deployed)

The Play package `com.apporo.assistant.play` uses this Worker only for its privacy page and AI response reports; it has no account, pairing or remote phone connection here. The code is ported unchanged from `woowtech-assistant-relay`, where it has been live since 2026-11-12:

- `/privacy/play` (GET and HEAD) and `/privacy/play.css`: the Play privacy policy in `src/privacy-play.ts`, effective 2026-11-13.
- `/api/v1/ai-reports` and `/admin/ai-reports`: the `REPORTS` Durable Object (`ReportInbox`, migration `v3`), 30-day retention with hourly cleanup, 60 reports per source IP per hour. See [ai-reports.md](docs/ai-reports.md). Optional secret `REPORT_ADMIN_KEY` (32+ characters) is a review-only key; `scripts/review-ai-reports.py` reads it from `~/.apporo-report-admin/secret`.
- `[assets]` serves `public/` before the Worker; the Play foreground-service demo video goes in `public/play/`.

Deploy only after the owner chooses assistant-relay.apporo.ai as the Play privacy and report host, from the apporo.ai Cloudflare account as above. The signed-out homepage then tells visitors what the Play app uses.

## OAuth endpoint move to /apporo-relay/oauth2 (prepared 2026-11-15, not deployed)

The WOOW PaaS platform module will be installed on www.apporo.ai and owns `/oauth2/authorize`, `/oauth2/token`, `/oauth2/introspect` and `/oauth2/revoke` there. The relay therefore moves to `/apporo-relay/oauth2/*` on the same host. Only the paths change. Client ID, callback, scope, PKCE, lifetimes and the Odoo code/token tables stay the same, so while both path sets exist a token issued on one is valid, and revocable, on the other. Pairings, device credentials and website sessions live in this Worker's Durable Objects and survive every step.

Ship in this order. Each step can be reversed on its own.

| Step | What ships | Effect while it ships |
| --- | --- | --- |
| A1 | Odoo `apporo_relay_oauth` 18.0.1.1.0 (branch `feat/relay-oauth-dual-paths`): both path sets, same handlers; the consent form posts to the relay path | Odoo restarts: relay sign-in and the account page fail until it is back. Paired phones, MCP and CLI keep working because they never call Odoo. |
| A2 | Nothing. Check the relay paths on production (below). | None |
| A3 | This Worker from the same branch: calls only `/apporo-relay/oauth2/*` | As with every Worker deploy, the Durable Objects restart. Each connected phone's WebSocket closes and the app reconnects by itself (about 1–1.5 s backoff after an open session). A computer request in flight at that moment fails with a 5xx error; as after `delivery_unknown`, check the task before submitting it again. Website sessions and pairings stay. |
| A4 | Nothing. Wait at least one hour (the token lifetime) and confirm the legacy paths get no relay requests. | None |
| B | Odoo 18.0.1.2.0 (branch `feat/relay-oauth-drop-legacy`): relay paths only | Odoo restart as in A1. Must be live before the platform module is installed; it can share that maintenance restart. |

Production addon, checked 2026-11-15: manifest, controllers, models and data are identical to 18.0.1.0.0; only `tests/test_oauth.py` is older, and `controllers/oauth.py.pre-csp-20261111` is a leftover backup from the 2026-11-11 patch. Replace the whole `apporo_relay_oauth` directory so neither stays behind.

A2 checks need no credentials and write nothing. Cloudflare blocks some default user agents, so send a named one:

    UA=apporo-relay-probe/1
    curl -sS -A "$UA" -o /dev/null -w '%{http_code}\n' -X POST https://www.apporo.ai/apporo-relay/oauth2/token --data grant_type=probe       # 400, not 404
    curl -sS -A "$UA" -X POST https://www.apporo.ai/apporo-relay/oauth2/introspect --data client_id=probe                               # {"active": false}
    curl -sS -A "$UA" -o /dev/null -w '%{http_code} %{redirect_url}\n' https://www.apporo.ai/apporo-relay/oauth2/authorize            # redirect to /web/login, not 404
    npm run test:provider                                                                                                           # PASS (token_http_400)

The same probes on `/oauth2/*` must still answer the same way during stage A. Do not start A3 until all pass; `404` or `token_http_404` means Odoo is not serving 18.0.1.1.0 yet.

A3 runs from this directory in the apporo.ai Cloudflare account:

    npx wrangler whoami                      # the account must own apporo.ai; export CLOUDFLARE_ACCOUNT_ID=<that account> for the commands below
    npx wrangler deployments list            # must still show 1e0489b3; note its full ID: it is the rollback target
    npx wrangler secret list                 # OWNER_KEY must be listed; do not put it again
    npm ci && npm run check && npm test && npm run test:accounts
    npx wrangler deploy --dry-run
    npx wrangler deploy --keep-vars --tag "$(git rev-parse --short HEAD)" --message "Relay OAuth paths moved to /apporo-relay/oauth2"

Production, checked 2026-11-15, runs version `1e0489b3`, uploaded with Wrangler at 2026-11-13T11:46:53Z: Durable Objects `AUTH`, `RELAY` and `REPORTS`, migration tag `v3`, compatibility date 2026-11-10. That is the Google Play edition above, so it is live despite its heading. This change is built on `apporo/relay-play-prep-20261113` (`6e06a559`) and leaves `wrangler.toml` untouched: the deploy adds no migration and only the OAuth paths change. If `deployments list` shows another version, find its source before deploying.

Static assets are uploaded from `public/` with each deploy, and files missing there disappear from production. `origin/playstore/apporo-play-20261113` (`9ec745e0`, 2026-11-13T10:55:23Z, before that upload) adds `public/play/fgs-demo-20261113.mp4`, which the Play Console declaration links to; this branch does not have it. If `https://assistant-relay.apporo.ai/play/fgs-demo-20261113.mp4` is live, cherry-pick `9ec745e0` before deploying.

After A3: `/healthz` returns 200; `curl -sS -o /dev/null -w '%{redirect_url}\n' https://assistant-relay.apporo.ai/auth/start` starts with `https://www.apporo.ai/apporo-relay/oauth2/authorize?`; a test account signs in to `/account`; the account page of a paired test phone shows “Phone connected” again.

A4: in the `apun-odoo` log, relay requests now appear as `/apporo-relay/oauth2/...`. No `GET /oauth2/authorize` or `POST /oauth2/token|introspect|revoke` should follow the switch; nothing else uses those paths until the platform module is installed.

After B: the A2 probes on `/apporo-relay/oauth2/*` answer as before, the same probes on `/oauth2/*` return 404 until the platform module answers them, and a test account still signs in to `/account`.

Rollback:

- A1 fails: put the 18.0.1.0.0 files back and restart Odoo. The Worker still uses the legacy paths.
- A3 fails: `npx wrangler rollback <full ID of 1e0489b3, noted before A3> --message "<reason>"`. Stage A Odoo still serves the legacy paths, and sessions created by the new version stay valid there. The rollback restarts the Durable Objects again, so phones reconnect once more.
- B fails: put the 18.0.1.1.0 files back and restart Odoo.
- Roll the Worker back to a legacy-path version only while Odoo serves 18.0.1.1.0. Never pair Odoo 18.0.1.0.0 with this Worker; sign-in would get 404. Once the platform module is installed the legacy paths are its own, and only Worker versions that call `/apporo-relay/oauth2/*` remain valid rollback targets.

## Release and recovery

1. Review and merge the source change. Run the Worker TypeScript, protocol, account-isolation and CLI-header tests, plus the Android and Odoo source checks. Verify the production Odoo addon matches the reviewed source.
2. Deploy the reviewed Worker with Wrangler in the apporo.ai Cloudflare account. Do not reset Durable Object data or replace its unique `OWNER_KEY`. Verify DNS/HTTPS, `/healthz`, Odoo login, the downloaded CLI's `User-Agent`, and a personal MCP `initialize` and `tools/list` call.
3. Build the Apporo release APK from the merged commit, sign with the existing Apporo certificate, check package/version/signature and GPL source archive, then publish through the existing Apporo release channel. Confirm the public asset hash and .7 → .8 update path.
4. If the Worker is unavailable, inspect deployment logs and redeploy a reviewed prior Worker version without deleting Durable Objects. If a phone must be disconnected, revoke it in the authenticated account page; the computer then receives `device_offline`. Pair again with a fresh one-use code on the phone.

Do not deploy this Worker on relay.apporo.io, assistant-relay.woowtech.io, or a Cloudflare account selected solely by a copied configuration value.
