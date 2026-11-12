# Play disclosures and privacy policy working draft — io.woowtech.assistant

> **Outdated worksheet, do not submit:** The remote relay, MCP and foreground-service inventory below predates the current Play edition. Reconcile against the final AAB and real data flows; see `PLAY_REVIEW_READINESS_2026-11-12.md`.

Drafted 2026-11-12 from the repository. This is a review worksheet and proposed policy wording, **not completed Play Console answers or a published privacy policy**. Verify against the final release AAB, actual network traffic, third-party SDK behavior, and operator practices before publication. Do not submit a “no data collected” answer merely because conversations and memory are saved locally: selected online model and speech providers receive user content.

## Product and data-flow evidence

- `app/build.gradle.kts` sets the Play edition package to `io.woowtech.assistant`; `app/src/woowtech/resources/brand.properties` names WOOW TECH CO., LTD. and `woowtech@designsmart.com.tw` as support contact.
- `app/src/main/AndroidManifest.xml` declares internet, microphone, notification, network-state, wake-lock, and foreground-service permissions; `allowBackup=false`. The Play manifest no longer declares AccessibilityService, APK installation, broad photo access, or the shell handoff provider. Recheck the merged release manifest.
- `app/src/main/java/com/wangzan101/mika/voice/VoiceInput.kt` selects Android speech recognition or a configured provider; provider speech sends recorded audio for transcription. Android speech service behavior depends on the device/service.
- `app/src/main/java/com/wangzan101/mika/memory/MemoryRuntime.kt` uses an encrypted local memory file and offers `wipeAll()`. `app/src/main/java/com/wangzan101/mika/chat/ConversationStore.kt` stores conversations locally and supports deleting a conversation. `app/src/main/java/com/wangzan101/mika/browser/UserBrowser.kt` stores browser history/favorites and uses WebView cookies.
- The Play research note (`PLAY_STORE_RESEARCH_2026-11-11.md`) records that the relay forwards tasks while the phone is online; it has **no implemented server-side conversation/attachment storage or offline sync API**. The listing makes no sync claim. Account creation for a WOOWTECH account is not established in the repository.
- The App now offers a user-initiated AI-response report action. It stores the selected response, category, optional note, and delivery status in private local files, then submits them to the relay's report endpoint. The relay implementation retains accepted reports for up to 30 days, but production deployment and operator access practices still require verification.

## Privacy policy text for operator review

**Privacy Policy — woowtech agent / 渥屋助理 (io.woowtech.assistant)**

**Operator:** WOOW TECH CO., LTD. / 渥屋科技股份有限公司

**Privacy contact:** woowtech@designsmart.com.tw

**Effective date:** [set on publication]

woowtech agent lets you connect an AI model using an account or API key that you provide. When you send a prompt, the app sends the prompt and relevant conversation context to the model service you selected so it can return a response. If you attach a photo or file, its contents may be sent to that model service when used in a request. The selected provider processes this information under its own terms and privacy policy. Please avoid sending information you do not want that provider to receive.

If you use voice input, the app requests microphone access while recording. Depending on your choice and device, audio is processed by an Android speech-recognition service or sent to your selected transcription provider. The resulting text can be used as a prompt. If you use the built-in browser, websites you visit can receive normal web requests and may set cookies or collect data under their own policies. The app stores browser history, favorites, site settings and cookies on the device.

Conversation history, personal memories, and selected attachments are stored in the app's device storage. Memory data is encrypted locally. You can delete individual conversations and memories and clear saved memory in the app. Uninstalling the app removes its private local data under Android's normal app-data behavior; this app disables Android backup. Deleting local data does not delete copies already sent to a model provider, speech service, website, or other external service. Use those services' controls for their copies.

If you enable the optional remote relay, the app maintains a connection to the configured gateway so an authorized client can send a remote conversation request and receive its response while the phone is online. The current edition does not provide cloud history or attachment synchronization. Before publication, add the gateway operator, categories of relayed data, security controls, retention period, and deletion process here, or remove the relay feature from the release.

If you choose to report an AI response, the app sends the selected response, your report category and optional note to WOOWTECH's relay. Reports remain in the app's private storage until delivery is acknowledged or you remove the app data. The proposed relay intake retains accepted reports for up to 30 days; confirm the deployed service, operator access, and deletion process before publication.

We use data to provide the features you request and to maintain the app. [Operator to confirm whether any diagnostics, support submissions, or server logs are received, their purpose, recipients, security measures, and retention period.] The app's code does not establish the retention or deletion practices of external AI providers, Android speech services, websites, or a remote gateway. Review their terms before use.

For privacy questions, contact woowtech@designsmart.com.tw. [Add the date and a published change-notice method before release.]

**Publication gate:** Replace every bracketed item, verify this wording against the shipped app and actual service contracts, host it at one active public non-editable web URL, and link it both in Play Console and within the app. [Google's User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en) requires developer/contact identity, data categories and recipients, secure handling, retention, deletion, and a public policy URL.

## Data safety form worksheet (verify before selecting answers)

Google's [Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en) applies across all active Play versions and includes third-party SDK behavior. “Collected,” “shared,” optionality, encryption in transit, and deletion answers must be decided from actual flows and provider roles, not from permissions alone.

| Data or practice | Repository evidence | Draft Console treatment / verification |
| --- | --- | --- |
| Prompts, conversation context, AI answers | User-selected model calls; local conversation store | Declare user-generated content/other app activity as applicable if transmitted. Map exact Console categories, purpose (“app functionality”), optionality, and recipient/provider role. |
| Photos and files chosen as attachments | Android pickers; conversation workspace | Declare photos/videos or files/docs if sent to a model or relay. Verify whether any attachment is uploaded automatically, retained remotely, or only held locally. |
| Recorded audio and speech text | `VoiceInput` supports Android speech service and provider transcription | Declare audio if transmitted to a provider; distinguish on-device recognition. Verify device recognition-service behavior and provider retention. |
| Model account credentials/API keys | Provider settings and sign-in flows | Verify whether credentials stay on device, are exchanged with the provider, or reach WOOWTECH infrastructure. Map any personal info/identifiers only after tracing requests. |
| Browser URLs, cookies and website data | WebView, local recent pages/favorites | Verify WebView/website/SDK transfers and Console scope. Document that websites have separate practices. |
| Memory and local conversation history | Local files; encrypted memory; backup disabled | Do not count device-only storage as network collection without a transfer. Confirm which memory/context is included in model requests and any relay request. |
| Optional remote relay | `McpRuntime` outbound relay, no sync API | Verify operator, request/response payloads, logs, encryption, access control, and retention. Do not claim cloud sync or deletion of data never stored. |
| User-submitted AI response reports | `AiResponseReports.kt`, `AiResponseReportDelivery.kt`; relay report inbox | Disclose selected response and optional note, purpose of moderation/support, operator access, up-to-30-day relay retention, local queue, and deletion controls. Verify production deployment and actual traffic. |
| Diagnostics and identifiers | Debug/perf trace code exists; no release analytics conclusion from this review | Audit final SDKs, release trace paths, support reports, crash/network logs, and device identifiers. |
| Ads | No ad flow found in this review | Confirm dependencies and final build before selecting “No ads.” |
| Account deletion | No confirmed WOOWTECH account creation flow | If the release allows creation of a WOOWTECH account, add both in-app and external deletion routes and declare them; provider accounts are separate. See [account deletion policy](https://support.google.com/googleplay/android-developer/answer/18265346). |

## Foreground-service declaration candidates

The current main manifest lists `TaskService`, `McpService`, and `ChatGptSignInService` as `specialUse`, plus `SandboxService` as `dataSync`. For each service **actually present and used** in the final AAB, Play Console requests a feature description, effect of delay/interruption, and demonstration video under its [FGS declaration guidance](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en). Re-evaluate the declared type and whether the service is needed; text below is a draft, not a claim of eligibility.

| Service | Candidate description | Delay or interruption / video evidence to prepare |
| --- | --- | --- |
| `TaskService` | Runs a user-started AI conversation or in-app web task and displays progress. | Delaying postpones the answer; interruption stops the current run and may require retry. Show user start, visible progress/notification, and stop. |
| `McpService` | Maintains a user-enabled outbound relay connection for authorized remote conversation requests. | Delaying or stopping disconnects remote access until reconnection. Show opt-in, paired state, persistent notification, and disable control. Verify the shipped relay scope and whether this service/type remains. |
| `ChatGptSignInService` | Keeps a user-started model-provider sign-in session alive while the external browser completes login or device-code polling. | Interruption may require sign-in again. Show the start, external browser, completion, notification, and cancellation. Confirm actual lifecycle and provider naming. |
| `SandboxService` | Prepares the bundled local runtime while needed for a retained feature. | Confirm whether the Play edition still starts this service. If retained, document the user-visible purpose, impact of deferral, stop control, and demo; otherwise remove its declaration. |

## Other required review entries

- **App access:** Supply persistent reviewer credentials or a test provider/API key if AI chat is gated by account setup. Do not place secrets in this document. Explain any external sign-in or regional constraints in Console. [Play review guidance](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en).
- **AI-generated content:** The App action and relay receiver are implemented in this branch, but the production receiver and end-to-end delivery are unverified. Complete those checks before declaring this flow operational in Play Console. [AI-generated content policy](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en).
- **Content rating, target audience, ads, and other App content forms:** Complete from the final app and Console questionnaire; this repository review does not establish definitive selections.
- **Assets:** If any submitted visual asset is AI-generated or edited, review the current [AI asset labeling declaration](https://support.google.com/googleplay/android-developer/answer/17262077?hl=en) for that asset.
