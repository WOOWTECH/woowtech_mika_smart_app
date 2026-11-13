# AI response reports (Play edition)

The native app may submit a report without a relay account, pairing, device token, cookie, or `Origin` header. Submission must be initiated by the user. Do not silently upload conversation history or diagnostics.

`POST https://assistant-relay.woowtech.io/api/v1/ai-reports`

`Content-Type: application/json`; body limited to 16 KiB:

```json
{"id":"123e4567-e89b-42d3-a456-426614174000","reason":"incorrect","note":"Optional user note","response":"The specific AI response being reported","created_at_ms":1794400000000}
```

`id` is a client-generated UUID; `reason` is one of `incorrect`, `unsafe`, `offensive`, `privacy`, `other`; `note` is at most 2,000 characters; `response` is required and at most 12,000 characters. `created_at_ms` is a Unix millisecond timestamp within seven days of submission. No other fields are accepted. An accepted request returns 201:

```json
{"id":"123e4567-e89b-42d3-a456-426614174000","accepted":true,"deletion_receipt":"private-opaque-token"}
```

The app should retain the deletion receipt locally if it offers report deletion. `DELETE /api/v1/ai-reports/{id}` with `Authorization: Bearer <deletion_receipt>` deletes that report and returns `{"id":"...","deleted":true}`. The receipt is returned only on initial submission and is not recoverable.

A retry with the same UUID also returns 201 `{"id":"...","accepted":true}` without a deletion receipt. It does not replace the stored report.

Operator review: `GET /admin/ai-reports` with `Authorization: Bearer <OWNER_KEY>` returns up to 50 reports and `next_cursor`; pass it as `?cursor=...` to continue. `DELETE /admin/ai-reports/{id}` with the same owner bearer deletes a report. These routes reject requests with an `Origin` header and require the owner key; do not expose that key to the app.

Reports reside in the relay's separate Cloudflare Durable Object storage for up to 30 days, with hourly expiry cleanup. Intake is limited to 60 attempts per source IP per hour (reviewers and offices may share one exit IP) and requires a Cloudflare source IP. The relay operator and Cloudflare infrastructure can access report content. No report is sent to the phone or stored in the conversation sync path. The application must disclose this upload and retention before submission.

Production deployment on 2026-11-12: Worker version `132d25e1-8925-4886-bfc9-a9c3bed61cce` uses migration `v3` and the `REPORTS` binding. A synthetic report returned 201 and was deleted with its receipt (200, then 404 on repeat). On POCO, the store Debug app retried an existing pending report, showed acknowledgement after relaunch, then its marked test report was deleted from the server and local test queue. This does not establish operator review access, 30-day expiry execution, or a user-facing deletion flow; those need separate acceptance.
