# Upstream provenance

This adapter draws on [WOOWTECH/woowtech-push-relay](https://github.com/WOOWTECH/woowtech-push-relay), branch `smart-mode`, inspected at commit `dff78a18d6bffc6a37c2e791e366fc96bc87656d`.

The upstream Apache License 2.0 is preserved verbatim in [UPSTREAM-LICENSE.md](UPSTREAM-LICENSE.md). This notice records attribution and modifications; it does not imply upstream endorsement or deployment compatibility.

- `contract.mjs`: closed-schema and token-validation patterns adapted from `functions/smart-validate.js`. Assistant targets and routes are new. The upstream `functions/smart-payload.js` was studied for Firebase message shape, but this adapter emits data-only messages, with no notification objects, text, APNs payload, or server-selected display settings.
- `errors.mjs`: conservative Firebase failure classification adapted from `functions/smart-notify.js`. Error names match the bot integration. Sender/project mismatch preserves the registration and requests a pause.
- `adapter.mjs` and `adapter.test.mjs`: injected sender and safe error-response testing patterns informed by `functions/smart-notify.js` and `functions/test/smart-notify.test.js`; installation verification, service authorization and registration/deduplication seams are assistant-specific.
- `client.mjs` and `fromBotFrame`: integration informed by the researched bot `server/phone-push.ts`, its tests and `docs/phone-push.md`. The adapter requires explicit service/event identity and excludes bot content and names.

Localization and notification rendering are Android responsibilities; no runtime module imports an upstream text table.
