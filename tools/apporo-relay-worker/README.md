# Apporo Assistant remote relay

This is Apporo's own Cloudflare Worker and Durable Object relay for the Android app. It uses https://assistant-relay.apporo.ai and existing www.apporo.ai accounts. The website is English first. It does not share accounts, storage, pairing codes, or device credentials with the WOOWTECH relay or Apporo Smart's relay.apporo.io.

The identity provider is the narrow Odoo addon in ../apporo-relay-oauth. It implements authorization code + PKCE S256 for one public client, apporo-assistant-relay, with exact callback https://assistant-relay.apporo.ai/auth/callback. No Odoo password or session cookie reaches the Worker. Each Odoo user receives a stable, private relay tenant and one phone slot.

## Use

1. Sign in at the relay website with your Apporo account. Approve the identity request on www.apporo.ai.
2. Create a five-minute, single-use pairing code on your personal page. In Apporo Assistant open Settings → Connect to computer → Remote, enter the code and turn on remote access.
3. Copy the personal MCP or CLI URL from the website or paired app. Use the phone's separate MCP access token for computer access. The pairing code and device credential are not computer credentials.
4. To remove a phone, use Disconnect phone on the website. Signing out of the website only ends the browser session.

The relay forwards authenticated requests while the phone is online. It does not queue work for an offline phone and does not provide end-to-end encryption against the relay operator. The transport protocol stays mika-relay.v2 for compatibility. Computer clients that cannot send a Bearer token cannot use this MCP address yet.

## Develop and verify

Use Node.js 22.12 or newer. The local tests use an isolated fake identity provider and local Durable Objects; they do not authorize production accounts.

    npm ci
    npm run check
    npm test
    npm run test:accounts
    npx wrangler deploy --dry-run

npm run test:provider is a separate online transport probe. It expects the Odoo addon to be installed and sends an invalid synthetic code to /oauth2/token; it does not sign in. Production account login, phone pairing, and actual MCP task execution need separate acceptance after deployment.

The downloaded apporo-relay-cli.py is derived from Mika's Apache-2.0 CLI and supports Apporo's /r/<tenant> prefix. Its default product and Android package are Apporo Assistant. Keep upstream attribution and the bundled license.

See DEPLOYMENT.md, docs/security.md, docs/operations.md, and docs/app-integration.md.
