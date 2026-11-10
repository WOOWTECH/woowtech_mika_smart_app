# WoowTech Assistant Relay

完整繁體中文文件：[中繼網站總覽](../../docs-woowtech/assistant-relay.md) · [部署維運](docs/operations.md) · [資安邊界](docs/security.md) · [App 契約](docs/app-integration.md)。

Cloudflare Worker + per-account SQLite Durable Object implementation of Mika's `mika-relay.v2` gateway for `https://assistant-relay.woowtech.io`.

Users sign in with their existing `aiot.woowtech.io` account through OAuth authorization code + S256 PKCE. Each account receives its own relay tenant and one phone slot. The server derives the tenant from the session, not from user-submitted account identifiers. The Worker secret `OWNER_KEY` is internal; ordinary users never need it. A one-time pairing code creates a device credential; the separate phone access token remains opaque and is forwarded to the phone. Offline requests are not queued or replayed. The legacy `primary` relay is preserved.

## Use

App integration contract: https://assistant-relay.woowtech.io/docs/app-integration.md . Native apps can call `GET /device/info` with their existing **pairing deviceToken** to obtain the correct personal MCP/API URLs. This is not the phone's MCP access token. The legacy `/pair` response is unchanged for strict old clients. No APK changes are included here.

1. Open https://assistant-relay.woowtech.io and choose WoowTech login. Enter credentials only on `aiot.woowtech.io`, then approve the identity authorization.
2. On your account page, generate a one-time pairing code. In the phone, use gateway origin `https://assistant-relay.woowtech.io` and that code.
3. Use the personal MCP URL shown on the account page, with the phone's access token. Do not share pairing codes or tokens.
4. For Python CLI access, download `/downloads/woow-relay-cli.py`; it supports the personal `/r/<tenant>` URL prefix. The original origin-only CLI does not.
5. Revoking a phone disconnects that account's device. Website logout ends the website session, not the phone connection. Sessions last at most one hour; signing in again restores the same account's tenant.

Current limits per account: 240 requests/minute, eight concurrent requests, eight management operations/minute. HTTPS/WSS encrypts transport; this service is not end-to-end encrypted against the relay operator. Account-disable handling for existing device connections and monthly bandwidth quotas are not implemented.

## Deploy

```sh
npm ci
npm run check
npm test
npm run test:accounts
npm run test:provider
npx wrangler secret put OWNER_KEY
npx wrangler deploy --dry-run
npx wrangler deploy
```

The custom domain, Worker, and Durable Object are independent from `relay.woowtech.io`. Observability is disabled to match the WoowTech Paseo deployment. Never commit the owner key or place it in client configuration.

The dedicated Odoo public OAuth client is `woowtech-assistant-relay`, with exact callback `https://assistant-relay.woowtech.io/auth/callback` and scope `relay:identity`. Registration is performed by `tools/odoo-inspect.mjs --register`; configure `WOOWTECH_ODOO_MCP_URL_FILE` to an authorized private MCP URL file outside the repo (0600). No credentials are printed. The fake OAuth provider exists only in `wrangler.test.toml` and the test entrypoint, never the production entrypoint. See `DEPLOYMENT.md` for verified versus outstanding acceptance checks.

`test:provider` exercises the real provider transport in workerd against Odoo with an invalid synthetic code. Opt-in production acceptance: `node test/live-login.mjs --prod --browser` (requires `npx playwright install chromium`). This creates a temporary portal-only user and synthetic phone, then revokes the test device/tokens and archives the user. Never run it as a high-frequency monitor. No test credentials are printed or saved.
