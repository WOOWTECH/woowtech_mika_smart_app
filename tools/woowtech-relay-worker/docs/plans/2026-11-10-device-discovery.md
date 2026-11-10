# Device endpoint discovery Implementation Plan

**Goal:** Website-only support for apps to obtain the correct personal MCP endpoint without breaking existing pairing.
**Architecture:** Preserve the exact legacy /pair response. Add GET /device/info, routed by existing device credential and authenticated against its stored hash. No phone access-token lookup, new pairing or APK changes.
**Tech Stack:** Cloudflare Worker, Durable Objects, TypeScript, existing Node integration tests.

1. Add failing assertions in test/accounts.mjs for personal endpoint discovery, wrong token, no token, origin rejection, spoofed tenant, revoked device and independent second account. Add legacy discovery assertions in test/smoke.mjs.
2. Run npm run test:accounts to confirm the missing endpoint fails.
3. Implement route and authenticated, rate-limited read-only response in src/index.ts; preserve exact pair response fields for strict Kotlin decoder.
4. Publish docs/app-integration.md through the Worker with explicit credential types, schema, errors and app-side validation guidance; no secrets.
5. Run npm run check, npm test, npm run test:accounts, dry-run and deploy. Check public documentation and unauthenticated endpoint. Extend live test to exercise discovery with its synthetic phone; never alter the user's paired phone.
6. Record deployment and hand off public contract URL. App implementation belongs to another conversation.
