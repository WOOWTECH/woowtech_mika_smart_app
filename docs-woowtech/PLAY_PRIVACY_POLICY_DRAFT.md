# Privacy Policy — woowtech agent / 渥屋助理 (Google Play edition)

> **Outdated draft, do not publish:** The relay pairing and account sections below predate the decision to remove computer connection from the Play edition, and this draft does not fully describe outbound MCP servers. Reconcile every section with the final app and actual report-delivery service before use. See `PLAY_REVIEW_READINESS_2026-11-12.md`.

- **Operator:** WOOW TECH CO., LTD. / 渥屋科技股份有限公司
- **Android package:** `io.woowtech.assistant`
- **Privacy contact:** woowtech@designsmart.com.tw
- **Effective date:** [OPERATOR DECISION: set when published]

This policy describes the Google Play edition of woowtech agent. Its optional online features handle data differently from information kept on your phone. The direct-download edition is a separate app and is outside this policy.

## Information kept on your phone

The app stores conversation history, personal memories, selected attachments, model settings and credentials, and browser history, favorites, site settings, and cookies on your device. Memory data and saved model credentials use local encryption. Android app backup is disabled. You can delete individual conversations and use the app's memory controls to remove saved memories. These actions affect local copies; they do not erase information already sent to another service. The app also keeps a local copy and delivery status of AI response reports that you submit; its local report retention period is not yet established.

## Model and speech services you choose

When you send a message to an online model, the app sends your prompt and relevant conversation context to the model provider you selected. Photos, files, or memory content included in a request can also be sent to that provider. The provider may process or retain that information under its own terms and privacy policy. Model account sign-in and API key use involve the selected provider. The app does not determine that provider's retention or deletion rules.

Voice input may use an Android speech-recognition service on your device or send recorded audio to the transcription provider you selected. The resulting text can become part of a model request. Whether an Android speech service processes audio on the device or sends it elsewhere depends on that service and device. Websites opened in the built-in browser receive normal web requests and may set cookies under their own policies.

## Optional WoowTech relay and account

If you enable the remote connection, a paired client can send requests through WoowTech's relay while your phone is online. An authorized client can request remote conversations and read conversations and eligible attachments stored on the phone. The relay forwards request and response contents, including any text or attachment bytes requested, through Cloudflare infrastructure. HTTPS/WSS protects transport, but the relay terminates that connection and can technically read the forwarded content; this is not end-to-end encryption from client to phone. The application relay code does not persist forwarded request or response bodies as conversation history and does not queue requests for an offline phone. [OPERATOR DECISION: confirm Cloudflare platform logging, caching, backups, and retention before publication; absence of application body storage is not a claim that infrastructure retains nothing.]

Relay website sign-in uses WoowTech's Odoo identity service. The relay stores a mapping from the Odoo account identifier to a stable relay account identifier, as well as pairing information. That account mapping persists across sign-outs. Signing out ends the website session; it does not remove the mapping or revoke a paired phone. The current service has no account-deletion route. [OPERATOR DECISION: define and implement the in-app and web account-deletion request paths, what Odoo/relay records they remove, any lawful retention exceptions, and the time to fulfill requests. Do not publish a deletion promise until it is operational.]

## AI response reports

If you choose **Report AI response**, the app sends the selected response text, your reason and optional note, and a report identifier to WoowTech's report inbox. It does not send the full conversation as part of that report request. Reports may wait on your phone until delivery succeeds or you retry. Accepted reports are stored in a Cloudflare Durable Object with a 30-day expiry and scheduled cleanup; an authorized operator can review them. A deletion receipt may be returned for an accepted report. [OPERATOR DECISION: document how users can use the receipt or contact WoowTech to request early deletion, and verify whether report data appears in infrastructure logs or backups.]

## Retention, deletion, and questions

Local conversation and memory controls remove the corresponding on-device data. Copies already sent to model providers, speech services, websites, an authorized remote client, or infrastructure are outside those controls. The report inbox's configured expiry is 30 days; no fixed period is stated here for local data, relay account mappings, Odoo account data, or infrastructure records because those periods have not been established. For privacy questions, contact woowtech@designsmart.com.tw. [OPERATOR DECISION: publish specific retention, deletion, and request-handling terms for relay/Odoo account records and infrastructure before release.]

---

## Publication checklist — remove this section and all bracketed decisions from the public policy

1. Set an effective date; confirm the operator identity and contact are correct. Obtain the operator's decisions on Cloudflare logs, cache, backups, security controls, and retention. Confirm final app and service traffic against this text.
2. Implement and document an in-app path and a public web resource for deleting the WoowTech relay account and associated data if the Play app offers account creation, including account creation reached through external sign-in. Specify any retention exceptions and request handling. Do not treat sign-out or phone unpairing as account deletion.
3. Verify local report retention and whether users can invoke the report deletion receipt; state the actual process. Confirm the 30-day server expiry and scheduled cleanup in the deployed service.
4. Reconcile Play Console Data safety, the listing, and in-app copy with online model/speech transfers, authenticated remote reads, the report inbox, Odoo account mapping, and all service providers. Host the final policy at a stable public URL and link it in Play Console and the app.

### Source notes for review — also remove before publication

- Local data and model/speech flows: `app/src/main/java/com/wangzan101/mika/chat/ConversationStore.kt`, `memory/MemoryRuntime.kt`, `settings/ProviderStore.kt`, `voice/VoiceInput.kt`, and `app/src/main/AndroidManifest.xml`.
- Remote reads and forwarding: `app/src/main/java/com/wangzan101/mika/mcp/McpRuntime.kt`, `mcp/PhoneConversationData.kt`, `core/src/main/kotlin/com/wangzan101/mika/core/remote/RemoteTaskApi.kt`, and `tools/woowtech-relay-worker/src/index.ts`.
- Account mapping and sessions: `tools/woowtech-relay-worker/src/auth.ts` and `docs/security.md` in that worker.
- Report payload, local queue, and server expiry: `app/src/main/java/com/wangzan101/mika/ui/AiResponseReports.kt`, `ui/AiResponseReportDelivery.kt`, and `tools/woowtech-relay-worker/src/reports.ts`.
