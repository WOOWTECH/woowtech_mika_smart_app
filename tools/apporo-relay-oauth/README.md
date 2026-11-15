# Apporo Assistant relay identity provider

Odoo 18 addon for the existing Apporo website at https://www.apporo.ai. It adds only the relay's OAuth routes: GET/POST /apporo-relay/oauth2/authorize for logged-in users and POST /apporo-relay/oauth2/token, /apporo-relay/oauth2/introspect, /apporo-relay/oauth2/revoke for the Cloudflare relay. It does not replace the website's login page or expose Odoo business records to the relay.

The single public client ID, exact callback and identity-only scope are fixed in controllers/oauth.py. Authorization codes are single-use, expire in ten minutes and require PKCE S256. Access tokens expire in one hour and are checked against the user's active status on every introspection. Only SHA-256 hashes are stored in the Odoo database. A daily cron removes used, revoked and expired records.

Install as a normal Odoo module by adding this directory's parent to addons_path and installing apporo_relay_oauth. Run its post-install HttpCase on an isolated Odoo test database before production. Back up the Apporo Odoo database before production installation. The Worker must be configured for https://www.apporo.ai and client apporo-assistant-relay; no secret is registered on the Odoo side because the client is public and PKCE-bound.

The Odoo password and website cookie remain at www.apporo.ai. A relay session, phone pairing code, device credential and MCP access token are separate. Revoking the Odoo identity token or disabling the user invalidates website sessions on their next check; an already paired phone must be disconnected separately from the relay account page.

## Endpoint move: stage A (18.0.1.1.0)

The bare /oauth2/* paths on www.apporo.ai are reserved for the WOOW PaaS platform module, which will be installed on the same website. 18.0.1.0.0 served the relay there. This version answers the relay paths and the legacy /oauth2/authorize, /oauth2/token, /oauth2/introspect and /oauth2/revoke with the same handlers, so the deployed Worker keeps working while it switches. The consent form always posts to /apporo-relay/oauth2/authorize. Codes and tokens are stored once, so a token issued on one path is valid, and can be revoked, on the other.

Stage B (18.0.1.2.0) removes the legacy paths. Install it only after the Worker calls the relay paths and the legacy paths no longer receive relay requests. Do not install the platform module while this addon serves /oauth2/*. The upgrade touches no data: replace the addon files, upgrade the module and restart Odoo. The switch-over order, checks and rollback are in ../apporo-relay-worker/DEPLOYMENT.md.
