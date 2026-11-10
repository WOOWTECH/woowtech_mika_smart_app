# Login callback incident — 2026-11-10

## Confirmed cause

The real Odoo login and consent succeeded, but the relay callback returned HTTP 502. The public page incorrectly collapsed that server error into a message suggesting an incomplete or expired login.

`AccountAuth.provider()` used `fetch(..., {redirect: 'error'})`. Cloudflare Workers does not support this redirect mode; it throws a TypeError before sending the request. Therefore the authorization code was issued but never exchanged. See https://developers.cloudflare.com/workers/runtime-apis/request/ .

The earlier two-account tests overrode the entire provider implementation, hiding the runtime incompatibility. A live HTTP acceptance test reproduced the reported symptom with a temporary portal-only Odoo user, and the workerd provider regression reproduced `token_fetch_typeerror` independently.

## Changes

- Use `redirect: 'manual'` and reject non-2xx results. Never follow a redirect with OAuth credentials.
- Retain PKCE, state/browser binding, one-use callbacks and fail-closed identity checks.
- Return bounded, non-sensitive error codes for network, HTTP, JSON, identity and login-state failures. Do not log raw exceptions, cookies, tokens or authorization URLs.
- Render a mobile-readable error page with retry/home buttons, the existing shared WoowTech stylesheet, and separate explanations for denied consent, missing cookies, stale login and server failures.
- Add a real workerd provider regression and opt-in production acceptance script. The latter creates a temporary portal-only user, uses actual password login and OAuth consent, then revokes its tokens and archives the user. It never resets any existing user's password or touches their pairing.
- Browser testing caught the new retry form being blocked by `form-action 'self'` when it redirected to Odoo. Retry now uses a navigation link instead; the CSP was not relaxed. The browser suite explicitly exercises denial followed by retry and approval.

## Reproduction / verification commands

```
npm run check
npm test
npm run test:accounts
npm run test:provider
node test/live-login.mjs --prod
# Browser acceptance additionally needs: npx playwright install chromium
node test/live-login.mjs --prod --browser
```

The provider test makes a real outbound request with an invalid synthetic code; it requires aiot availability. The production script changes only its temporary user's records and relay tenant. Do not run it as an unattended high-frequency monitor.

## Verified so far

Before the fix, the production callback consistently returned 502 and the workerd regression failed with `token_fetch_typeerror`. After the fix, the same commands passed: real Odoo password login, consent, callback, personal account, single-use pairing, synthetic-phone WSS v2 forwarding, wrong phone-token rejection, revoke confirmation, device revocation and logout. Local two-user isolation and legacy smoke suites also passed.

The synthetic phone does not prove POCO operation, Android background survival, Wi-Fi/mobile switching, or physical-device interaction. The original user's browser retest remains separate from automated acceptance. Multi-account monthly bandwidth quotas and automatic device revocation on account disable remain unimplemented; they are not silently treated as passed.

Final Chromium mobile-mode acceptance passed actual password login, denial/retry/approval, browser-managed cookies, stable tenant across repeat login and logout. Landing/error pages passed 320/360/1280px overflow, text-size and touch-target checks; mobile screenshots were inspected. Final deployed version: `d24eac80-4669-4782-b389-0052eac07a5b`.
