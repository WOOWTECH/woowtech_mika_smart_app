# Operations

The Apporo relay is a separate Cloudflare Worker + Durable Objects service. Its identity provider is the Apporo Odoo addon in tools/apporo-relay-oauth. Node.js 22.12+ and the pinned Wrangler version are required.

Run npm ci, npm run check, npm test, and npm run test:accounts before deployment. Wrangler deploy --dry-run checks the bundle, but does not verify Cloudflare ownership or live Odoo login. npm run test:provider is an opt-in probe of Odoo's token endpoint using an invalid code after the addon is installed.

Sign in with Wrangler using the Apporo Cloudflare account. Verify that its account owns the apporo.ai zone before any secret or deploy action. Store OWNER_KEY in Cloudflare Worker secrets; use a unique, randomly generated value of at least 32 bytes. Never put it in the repository, a CLI argument, a screenshot or chat. The browser's Odoo login, phone pairing code, device credential, phone MCP token and owner key are five distinct credentials.

The Odoo addon fixes the single client ID, exact callback and relay:identity scope in source. It does not create an editable oauth_client record. Installing this addon is the provider registration. After deployment, a consent request must identify Apporo Assistant remote access and return to the exact Cloudflare callback. The Odoo password must be entered only at www.apporo.ai.

For acceptance use a dedicated test Apporo account and a test phone. Test real login and denial, one-time pairing, personal URL isolation, /device/info, WSS reconnect, MCP initialize/tools, CLI task and cancellation, revoke and logout. A synthetic phone proves protocol transport but is not a substitute for an Android app run. Never revoke a user's production device to test cleanup.

If /healthz works but MCP returns device_offline, check the correct personal /r/<tenant> URL, the phone's remote switch and WebSocket status. Do not retry task submission automatically after delivery_unknown; inspect the task first. Browser logout does not revoke pairing. Device revocation does not change the user's Odoo password.

Code rollback does not reverse Durable Object migrations or Odoo database records. Keep service backups and preserve both RELAY and AUTH storage. Emergency shutdown must affect only assistant-relay.apporo.ai, never the WOOWTECH relay or Apporo Smart's relay.apporo.io.
