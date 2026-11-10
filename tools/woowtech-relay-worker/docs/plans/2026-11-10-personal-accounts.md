# Personal WoowTech accounts implementation plan

Goal: Shared relay site using aiot.woowtech.io accounts, with one isolated phone per account and independent quotas.

Architecture: Existing Odoo OAuth authorization-code + S256 PKCE, exact callback, identity-only scope. A separate Auth Durable Object stores short-lived login intents and opaque browser sessions; server-side token introspection binds immutable Odoo subject to a stable opaque tenant ID. Each tenant has its own Relay Durable Object. Existing single-owner primary instance and phone credentials remain supported.

1. Inspect prod OAuth client schema via Odoo MCP. Register a dedicated public PKCE client with exact /auth/callback redirect and identity-only scope. No existing client changes.
2. Add auth.ts: start/callback/logout, secure HttpOnly SameSite cookies, state binding, one-time intents, token introspection, session expiry and per-operation origin checks.
3. Add account.ts: authenticated dashboard, server-derived tenant, individual pairing/status/revoke, dedicated MCP/CLI URL. No browser-supplied owner identity trusted.
4. Modify index.ts: route new codes/device tokens to tenant DOs while preserving 43-character device tokens and root gateway origin accepted by existing Android. Tenant-specific protocol URL rewrites, no shared phone token storage.
5. Quotas: persisted per-account control/relay counters and concurrent request bounds. Verify one account cannot consume another's quota or revoke another's device.
6. Test with mock OAuth over the local Worker runtime: login state replay/forgery, two distinct subjects, pairing, authorization forwarding, cross-account rejection, logout, legacy route compatibility. Run TypeScript and existing smoke.
7. Deploy only after local tests pass. Verify real authorize redirect and live unauthenticated protections. Actual existing-account login needs user browser consent; never claim synthetic OAuth tests verify a human login.

Rollback: previous Worker version cd0c8bd3-1c98-4560-bdfa-e49340fe2d79; preserve existing DO class and migration. OAuth client can be independently disabled. Do not touch other Odoo client records.
