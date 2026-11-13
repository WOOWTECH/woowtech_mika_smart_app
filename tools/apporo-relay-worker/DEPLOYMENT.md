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

- `/privacy/play` (GET and HEAD) and `/privacy/play.css`: the Play privacy policy in `src/privacy-play.ts`. Set its effective date on the day it goes live; `RELAY_LIVE=1 node test/smoke.mjs` refuses the placeholder.
- `/api/v1/ai-reports` and `/admin/ai-reports`: the `REPORTS` Durable Object (`ReportInbox`, migration `v3`), 30-day retention with hourly cleanup, 60 reports per source IP per hour. See [ai-reports.md](docs/ai-reports.md). Optional secret `REPORT_ADMIN_KEY` (32+ characters) is a review-only key; `scripts/review-ai-reports.py` reads it from `~/.apporo-report-admin/secret`.
- `[assets]` serves `public/` before the Worker; the Play foreground-service demo video goes in `public/play/`.

Deploy only after the owner chooses assistant-relay.apporo.ai as the Play privacy and report host, from the apporo.ai Cloudflare account as above. The signed-out homepage then tells visitors what the Play app uses.

## Release and recovery

1. Review and merge the source change. Run the Worker TypeScript, protocol, account-isolation and CLI-header tests, plus the Android and Odoo source checks. Verify the production Odoo addon matches the reviewed source.
2. Deploy the reviewed Worker with Wrangler in the apporo.ai Cloudflare account. Do not reset Durable Object data or replace its unique `OWNER_KEY`. Verify DNS/HTTPS, `/healthz`, Odoo login, the downloaded CLI's `User-Agent`, and a personal MCP `initialize` and `tools/list` call.
3. Build the Apporo release APK from the merged commit, sign with the existing Apporo certificate, check package/version/signature and GPL source archive, then publish through the existing Apporo release channel. Confirm the public asset hash and .7 → .8 update path.
4. If the Worker is unavailable, inspect deployment logs and redeploy a reviewed prior Worker version without deleting Durable Objects. If a phone must be disconnected, revoke it in the authenticated account page; the computer then receives `device_offline`. Pair again with a fresh one-use code on the phone.

Do not deploy this Worker on relay.apporo.io, assistant-relay.woowtech.io, or a Cloudflare account selected solely by a copied configuration value.
