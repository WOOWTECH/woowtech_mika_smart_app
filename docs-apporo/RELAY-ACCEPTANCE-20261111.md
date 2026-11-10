# Apporo Assistant remote relay acceptance — 2026-11-11

Scope: dedicated Apporo Odoo identity provider, independent Cloudflare Worker source, and Android apporo.8 candidate. This is an implementation and partial acceptance record, not a public release receipt.

| Check | Result | Evidence / limit |
| --- | --- | --- |
| Odoo module in isolated database | PASS | Two post-install HttpCase tests, 0 failures: real consent approve/deny with exact callback and PKCE; wrong verifier, code replay, introspection and revoke. The isolated database and filestore were removed. |
| Production Apporo website | PASS for provider installation | A verified 42 MB custom-format database backup preceded installation. Module state became installed; www.apporo.ai homepage remained HTTP 200; invalid-token introspection returned active=false and malformed token exchange returned HTTP 400. The user's actual account login has not yet been exercised. |
| Worker local protocol | PASS | TypeScript check, legacy relay smoke and two-account tests: one-time pairing, per-account isolation, WebSocket forwarding, revoked-device rejection, browser/state binding, CSRF and logout. Dry-run bundle passed. |
| Worker → production Odoo transport | PASS for rejection path | Workerd sent a synthetic invalid code to the live Odoo token endpoint and received the expected HTTP 400 rejection. This does not prove a complete real-user login. |
| Android build | PASS | apporo.8 / 3808 Apporo debug variant assembled; this is a test certificate and cannot upgrade a public release build. |
| Android 16 emulator UI | PASS for unpaired screen | Opened Settings → Advanced & other → Connect a computer → Remote. English screen showed Apporo sign-in instruction, Open relay website button, prefilled https://assistant-relay.apporo.ai/ gateway and disabled pair action without a code. USB/Wi-Fi/Remote selector remained legible after shortening the USB label. The button opened Chrome with the intended host. Onboarding was bypassed in the debug emulator by setting local test preferences; no model key, actual pairing or remote task was used. |
| Public Cloudflare domain | PENDING | Wrangler device authorization was requested but expired before approval. No Worker, DNS route or owner secret was created. |
| Real account, phone and MCP | PENDING | Needs Cloudflare deployment, then real Apporo login/consent, phone pairing, personal MCP initialize/tool call, CLI task, revocation and logout. |

The Android screenshot and UI dump are retained under the local test evidence directory at ~/.local/share/apporo-assistant/test-evidence/relay-20261111. No pairing code, access token, Odoo password or Cloudflare credential is stored in this report.
