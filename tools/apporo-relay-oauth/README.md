# Apporo Assistant relay identity provider

Odoo 18 addon for the existing Apporo website at https://www.apporo.ai. It adds only four routes: GET/POST /oauth2/authorize for logged-in users and POST /oauth2/token, /oauth2/introspect, /oauth2/revoke for the Cloudflare relay. It does not replace the website's login page or expose Odoo business records to the relay.

The single public client ID, exact callback and identity-only scope are fixed in controllers/oauth.py. Authorization codes are single-use, expire in ten minutes and require PKCE S256. Access tokens expire in one hour and are checked against the user's active status on every introspection. Only SHA-256 hashes are stored in the Odoo database. A daily cron removes used, revoked and expired records.

Install as a normal Odoo module by adding this directory's parent to addons_path and installing apporo_relay_oauth. Run its post-install HttpCase on an isolated Odoo test database before production. Back up the Apporo Odoo database before production installation. The Worker must be configured for https://www.apporo.ai and client apporo-assistant-relay; no secret is registered on the Odoo side because the client is public and PKCE-bound.

The Odoo password and website cookie remain at www.apporo.ai. A relay session, phone pairing code, device credential and MCP access token are separate. Revoking the Odoo identity token or disabling the user invalidates website sessions on their next check; an already paired phone must be disconnected separately from the relay account page.
