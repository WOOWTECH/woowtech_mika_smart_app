# Deployment record

Status as of 2026-11-11: Apporo Odoo OAuth is installed on www.apporo.ai; the Cloudflare custom domain and release APK are not yet deployed. An apporo .8 arm64 APK with the final relay input layout has been locally built and signed as an unpublished test candidate. Its package identity and certificate match with the installed apporo .7 package were checked; an actual upgrade has not yet been tested. A public release needs a fresh artifact from the final reviewed commit. Update this record with real Worker version IDs and acceptance evidence after deployment.

The Odoo addon passed two post-install HttpCase tests in an isolated database: consent approval/denial with exact callback and PKCE, and one-time code, introspection and revoke. The test database was removed. Before production installation, a pg_dump custom-format backup was made and verified with pg_restore -l. Production module state is installed; the website home returned HTTP 200 and the introspection route returned an inactive response for a fake token. The Worker provider transport test also reached the real Odoo token route and got the expected rejection.

## Order

1. Authenticate Wrangler to the Cloudflare account that owns apporo.ai. Confirm the zone/account before deploying. The copied WOOWTECH account ID has deliberately been removed from wrangler.toml.
2. Create the independent Worker apporo-assistant-relay, bindings RELAY and AUTH, and a unique 32-byte-or-longer OWNER_KEY secret. Do not reuse the WOOWTECH key. Preserve Durable Object data during later deploys.
3. Deploy assistant-relay.apporo.ai. Check DNS and HTTPS, /healthz, anonymous login redirect, Odoo consent, account page, pairing, WebSocket, personal MCP/CLI paths, device discovery, revocation and logout.
4. Release an Apporo APK with the new gateway link and prefilled address through the existing Apporo release channel. Confirm it upgrades the installed Apporo package without changing its certificate or data.

Local tests passing are not evidence for production OAuth, DNS, actual Android connection or a model-driven remote task. Those checks remain outstanding until their own receipts are recorded.

Do not deploy this Worker on relay.apporo.io, assistant-relay.woowtech.io, or a Cloudflare account selected solely by a copied configuration value.
