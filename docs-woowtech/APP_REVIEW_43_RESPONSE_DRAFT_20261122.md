# Technical draft for the November 16 App Review questions — 4.3 / 4.2.6

**For Parent review; do not send with OWNERFACT placeholders unresolved.** Question numbering follows Parent's paraphrase of the actual rejection; Parent should retain Apple's exact question wording in the final reply. This draft supplies the technical portion, not an unsupported market-uniqueness claim or a declaration that all commercial requirements passed.

Parent-confirmed context: existing WOOW iOS version **1.0.0 / build 4**, uploaded November 15, was rejected November 16 under 4.3 and 4.2.6. Latest **0.1.0 (274)** is now VALID / IN_BETA_TESTING. This supersedes older documents' pending-processing observations, but does not prove a phone installed 274 from TestFlight. Parent owns the authenticated version/rejection reconciliation. The rejected build 4's exact source is not established in this audit.

Audited repository HEAD: `d9816f9151c3a93ec7e51e1499acfe42b6bf2856`; production iOS Sources, configuration, Package.swift and project.yml have no diff from runtime `611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`. All current-runtime claims below refer to that runtime. Source/metadata/document reads only; no account/metadata/auth access, private notes, secrets, customer orders, model calls, device/build/test work, screenshots, privacy re-audit, external contact or repository mutation.

## Proposed English answers

### 1. What problem does the app solve?

The app is designed to keep a user's AI-assisted work together across conversations, selected documents, web research and reusable personal context. Users select their model service, keep conversation and learning records on the device, inspect or edit remembered information, and turn selected source text or a reply into a native document. The technical objective is continuity between those activities rather than a chat screen whose only output is transient text.

**OWNERFACT Q1:** Add the specific recurring problem observed among actual intended users, the present workaround, and an approved concrete example. Source code cannot establish customer demand or quantify time saved.

Technical evidence: [ios/Sources/App/ChatSession.swift:51](../ios/Sources/App/ChatSession.swift:51) and [ios/Sources/App/ConversationArchiveStore.swift:5](../ios/Sources/App/ConversationArchiveStore.swift:5); [ios/Sources/App/LearningStore.swift:333](../ios/Sources/App/LearningStore.swift:333); [ios/Sources/App/DocumentExportView.swift:51](../ios/Sources/App/DocumentExportView.swift:51); document export introduced at `d699a767688109fbc5b49f57b4d0071e452779de` on November 20. These demonstrate implementation, not that no other app solves the same problem.

### 2. Who is the intended audience?

**OWNERFACT Q2:** “The intended audience is [specific users and their actual role/workflow], principally in [relevant markets/languages if substantiated]. They use the app to [verified repeated task].”

The implementation offers Traditional Chinese and English, iPhone/iPad support and user-selected model services. Those facts do not independently establish a target profession, customer segment, age group or geographic market. Do not substitute an invented enterprise, education, manufacturing or smart-home target.

### 3. What gap does it address compared with existing apps?

The implemented workflow connects document selection and local text extraction, model conversations, reviewable personal memory/skills, browser work and local PDF/HTML/CSV generation. These are native app workflows with their own storage, editor, preview and system handoff; the app is not limited to displaying a remote chat website.

**OWNERFACT Q3:** Explain which named alternative or current workflow the actual audience uses, the specific unmet requirement, and an approved demonstration showing that difference. We are not asserting that integrated chat, browsing, memory or document export is exclusive to this product, or that a feature list alone answers the duplication concern.

Technical evidence: [ios/Sources/App/DocumentExportView.swift:64](../ios/Sources/App/DocumentExportView.swift:64), [ios/Sources/AssistantDocuments/DocumentReport.swift:3](../ios/Sources/AssistantDocuments/DocumentReport.swift:3), [ios/Sources/App/ChatWebTaskSession.swift:62](../ios/Sources/App/ChatWebTaskSession.swift:62) and [ios/Sources/AssistantPersistence/EncryptedLearningFile.swift:105](../ios/Sources/AssistantPersistence/EncryptedLearningFile.swift:105). Native export is commit `d699a767...`; current implementation is included in runtime `611d6bfa...`.

### 4. What changed in response to beta feedback?

The documented feedback available for this response is controlled developer QA, including the original iPhone, plus native regression tests. It should not be described as an independent customer survey. Specific observed defects led to these changes, all included in runtime 611d6bfa / Release 274:

- Return navigation and transcript positioning across keyboard changes were corrected in `28deae96ca3a7718743d78e6d0ddc2a42d1be020`.
- A keyboard animation-timing property was publishing during a SwiftUI update. Commit `96317e5f54c343e43c23a447a1dccb02e9b3c5c4` removed that unnecessary publication while keeping frame publication and synchronous timing updates.
- An idle, empty, unfocused composer is refreshed after Dynamic Type changes in `4e2c8c643505f4306f2cc2cb4d1f5b644c2fd287`. Nonempty drafts are preserved.
- MCP execution logging previously recorded completion before classifying an error result. Commit `611d6bfa75ec46d39fd9654ac97ff2de6291a1a0` classifies returned/failed outcomes first, without logging tool arguments, server text or credentials.

Controlled Release-274 checks subsequently verified one empty-field font-restoration cycle; normal four-line draft/keyboard behavior; a one-page native PDF; maximum-font input/notice scrolling; and one public-page browser-history persistence cycle. The evidence register below gives the exact versions and limits.

**OWNERFACT Q4:** Identify any actual external beta participants, dated feedback and resulting changes that the owner can substantiate. Keep those distinct from controlled QA. No evidence here proves all live AI/MCP work is reliable: the November 22 20:53 model probe still displayed rate limiting, and intermittent source-read timeouts remain unresolved. We do not claim these latest changes were present in rejected build 4 or that every earlier test passed on 274.

Sources: [docs-woowtech/KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md:1](../docs-woowtech/KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md:1), [docs-woowtech/IOS_MCP_RESULT_DIAGNOSTIC_20261122.md:1](../docs-woowtech/IOS_MCP_RESULT_DIAGNOSTIC_20261122.md:1), [docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44](../docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44), [docs-woowtech/IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md:1](../docs-woowtech/IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md:1), [docs-woowtech/IPHONE_274_BROWSER_HISTORY_20261122.md:1](../docs-woowtech/IPHONE_274_BROWSER_HISTORY_20261122.md:1) and [docs-woowtech/IPHONE_274_SERVICE_PROBE_20261122.md:1](../docs-woowtech/IPHONE_274_SERVICE_PROBE_20261122.md:1).

### 5. Is this related to another app or a suite?

**OWNERFACT Q5:** Provide a complete, accurate related-app table: app name, bundle ID, public listing, publisher/ownership relationship, audience, primary job, and whether it is being maintained, consolidated or retired. Explicitly address **Apporo Assistant, com.apporo.assistant, Apple ID 6835318500**, and the owner-identified platform/smart/AIoT branded pairs.

Local Apporo iOS project metadata does exist; this is not an Android-only naming coincidence. Do not answer “no related apps” or “unrelated products” without resolving the relationship. Findings and limits appear below. No ownership, distribution history or current Apporo Store binary is inferred from local folder names.

### 6. Why should this be separate rather than a feature of another app?

**OWNERFACT Q6:** Explain the distinct, verified user task and product boundary, why users need this particular independent app, and why adding the function to an existing related app would not meet that need. Address Apporo directly and explain any genuine audience/content/service separation.

The source has an independent native application target and local data lifecycle. That shows it can operate as an application; it does not prove that separate App Store listings are necessary. Shared framework names or separate branding are not a substantiated reason that consolidation is technically impossible. If the products are substantially the same experience, the response should describe the owner's actual consolidation decision rather than invent distinctions.

### 7. Does it share significant code or assets with your other apps?

There is disclosed reuse and derivation. The repository's root NOTICE describes a modified Mika product, and ios/NOTICE documents Swift adaptations of Mika's memory, skill, website-knowledge and route behavior. The same repository also has Apporo and WOOW Android flavors using the common main source layout.

For the separate iOS listings, local Apporo project metadata declares eight of the same named core framework groups used by WOOW; the current WOOW project adds AssistantDocuments. This is a concrete relationship signal, not a measured percentage of shared implementation or artwork.

**OWNERFACT Q7 — required before sending:** State explicitly whether significant iOS code/assets are shared with Apporo or other portfolio apps; identify the shared modules, UI/content/branding assets, and the verified product differences. Correlate the comparison to the actual submitted/shipped Apporo and WOOW versions. If substantial reuse exists, disclose it. Do not claim zero shared code, unique artwork, or that a ninth framework alone establishes a different product.

Evidence: [NOTICE:7](../NOTICE:7), [ios/NOTICE:4](../ios/NOTICE:4), [app/build.gradle.kts:137](../app/build.gradle.kts:137), [ios/project.yml:111](../ios/project.yml:111), and the two Apporo project metadata files identified below. This audit intentionally did not compare another app's source files, icons, screenshots or binary.

### 8. What third-party material is used, and what did you contribute?

Yes, the product uses third-party open-source material beyond standard Apple frameworks. Mika is the disclosed Apache-2.0 upstream. ios/NOTICE identifies revision `0c172724f3f0c96f7345262588072f6e95db1138` for adapted behavior and the bundled skill archive. That archive contains verbatim copies of five upstream SKILL.md documents, three supporting files, LICENSE and NOTICE. Included scripts are inert reference text; they are not an embedded Python execution capability. Some Swift prompt/behavior comments also cite later upstream references, including `964d7bec`; do not describe every prompt as originally written for this app.

The audited Release-274 bundle contains nine repository-built Swift frameworks, and its Swift package manifest declares internal target dependencies without an external package-dependency list. Apple framework use is listed below. This does not make the imported material first-party, and “no external SDK dependency” must not become “no third-party code or content.”

Concrete iOS implementation work includes native document parsing/export and PDFKit preview/system handoff; encrypted transactional persistence and reviewable learning state; SwiftUI composer/keyboard behavior; bounded WebKit task integration; and MCP approval/execution/result handling. The source and dated commits below substantiate implementation work. They do not establish exclusive invention or the absence of common code in another owned app.

**OWNERFACT Q8:** Confirm who developed/commissioned the app, what reusable app builder/template or outside development service was actually used, if any, and rights/provenance for the submitted artwork and other assets. AI-assisted Swift authoring, if used, is a development method; it is not itself evidence that a commercial template was purchased, nor proof of originality. This bounded source audit cannot certify “no template/service ever used.” Explain the actual development process honestly.

Sources: root [LICENSE:67](../LICENSE:67) and [LICENSE:90](../LICENSE:90); [ios/NOTICE:4](../ios/NOTICE:4); [ios/Sources/AssistantSkills/BundledSkillCatalog.swift:73](../ios/Sources/AssistantSkills/BundledSkillCatalog.swift:73); [ios/Sources/AssistantSkills/ChatOutcomeJudge.swift:105](../ios/Sources/AssistantSkills/ChatOutcomeJudge.swift:105); [ios/Sources/AssistantSkills/SkillLearningService.swift:5](../ios/Sources/AssistantSkills/SkillLearningService.swift:5); [ios/Package.swift:4](../ios/Package.swift:4) and the contribution/evidence register below.

### 9. Who is the client/content provider, and who is submitting?

**OWNERFACT Q9:** Identify the legal publisher/account holder, whether this is an in-house product or commissioned for a client, who owns and operates the service/content, and the relationship among that entity, WOOW TECH and Apporo. If a development agency or template provider was involved, explain its role and who controls/maintains the application. Parent should ensure the actual submitting account and content-provider relationship are stated accurately.

The root NOTICE attributes WOOWTECH modifications and the upstream Mika copyright. That is source attribution, not verification of legal ownership, client contracts or the ASC submitting entity. Users' private documents and selected AI services must not be presented as proof that WOOW TECH owns a proprietary content catalog. No private contact or customer information is needed in this answer.

## Technical evidence register — internal, not a new test run

These references are local review aids. Parent can provide a concise approved appendix to Apple if useful; do not paste private paths, raw conversations, keys, customer data or unrelated QA details into Review Notes.

| Evidence / version | What is actually supported | Limit |
| --- | --- | --- |
| Document implementation, November 20, `d699a767688109fbc5b49f57b4d0071e452779de` | Adds local document-export flows on iOS and Android. iOS target AssistantDocuments plus native editor/store/preview. [ios/Sources/App/DocumentExportView.swift:64](../ios/Sources/App/DocumentExportView.swift:64), [ios/Sources/AssistantDocuments/DocumentReport.swift:59](../ios/Sources/AssistantDocuments/DocumentReport.swift:59). | Feature implementation is not proof of market exclusivity or a complete physical export/share matrix. |
| Keyboard fix `96317e5f...`, included in 274 | Native299 was 0/1 with a real extra publication; native300 was 3/3, zero failures/skips, including real PDF preview and existing keyboard/Return cases. [docs-woowtech/KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md:15](../docs-woowtech/KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md:15). | Simulator/native app regression with synthetic model; not a live model/customer case or proof every Publishing issue is fixed. |
| Idle typography `4e2c8c64...`, included in 274 | One real original-iPhone/iOS26.5 Development-signed Release274 empty-field cycle: 23 pt → maximum 64 pt → first observed restored 23 pt; later recorded observations at 6.2344 / 16.2317 / 31.2318 seconds remain 23 pt. [docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44](../docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44). | First observation is not the exact restoration instant; one controlled cycle, not every font/device. |
| Return/navigation `28deae96...`, included in 274 | Explicit Return control and keyboard-aware transcript work; controlled 274 normal four-line/keyboard and PDF-close follow-up provide limited physical evidence. [ios/Sources/App/ContentView.swift:1161](../ios/Sources/App/ContentView.swift:1161) and [docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44](../docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:44). | Does not close all long-stream/live-service or historical CPU defects. |
| MCP diagnostics `611d6bfa...` / native303 | 22/22, zero failures/skips, across 7 diagnostic + 10 runner + 5 actual TCP/HTTP loopback cases; actual OS log 222 events / 111 paired UUIDs. [docs-woowtech/IOS_MCP_RESULT_DIAGNOSTIC_20261122.md:9](../docs-woowtech/IOS_MCP_RESULT_DIAGNOSTIC_20261122.md:9). | Fixture/loopback, not a successful real Apporo/business-tool workflow; no retroactive classification of old errors. |
| Controlled Release274 local PDF | Real 39-character source → 19,434-byte, one-page PDF; PDFKit source-completeness check documented. [docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:52](../docs-woowtech/IPHONE_274_CONTROLLED_UPDATE_20261122.md:52). | Not multi-page generation, CSV success on this iPhone, external save, or recipient delivery. |
| Controlled Release274 maximum font | Seven field-only swipes reached the fourth-line end and returned to the start; two notice-area swipes reached the notice end and returned, retaining the same 47-character draft hash. [docs-woowtech/IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md:7](../docs-woowtech/IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md:7). | No product patch was justified by the earlier partial viewport. Does not mean four lines are simultaneously visible or every accessibility mode passed. |
| Controlled Release274 browser persistence | One public example.org navigation, history saved, one normal app restart, same history ID/text retained. [docs-woowtech/IPHONE_274_BROWSER_HISTORY_20261122.md:3](../docs-woowtech/IPHONE_274_BROWSER_HISTORY_20261122.md:3). | Not third-party login, every site, redirects/downloads or custom-search completion. |
| Failures remain in records | Release274 20:53 UI model probe returned a rate-limit message; intermittent 15-second source waits remain; no usable fault-window stack/root cause. [docs-woowtech/IPHONE_274_SERVICE_PROBE_20261122.md:3](../docs-woowtech/IPHONE_274_SERVICE_PROBE_20261122.md:3), [docs-woowtech/IPHONE_274_SETTINGS_RETURN_CONTROLS_20261122.md:3](../docs-woowtech/IPHONE_274_SETTINGS_RETURN_CONTROLS_20261122.md:3). | No claimed HTTP429 without raw evidence, no all-service/all-commercial PASS, and no additional probe performed here. |

All physical 274 rows above are **Development-signed Release runtime611d6bfa on the original iPhone**, not TestFlight-installed 274. Parent's newly authenticated VALID / IN_BETA_TESTING status is a separate distribution fact. Do not merge simulator counts, private evidence-file counts or independent re-verifications into additional physical passes.

Version source: [docs-woowtech/TESTFLIGHT_274_RELEASE.md:13](../docs-woowtech/TESTFLIGHT_274_RELEASE.md:13). The Store IPA previously independently checked is 0.1.0(274), SHA-256 `d72102f5d992bc2458aaff7c15ff0e8cdae8061eeee79d0dad15a6111b79dcf0`, main UUID `7CE1BB7D-7066-3E04-B2F8-8280E33F5B05`. No build was made for this response.

## Provenance, bundled material, and framework inventory

- Root LICENSE is Apache License 2.0. Root NOTICE explicitly identifies a modified Mika product and disclaims upstream endorsement. ios/NOTICE records the Swift adaptations; licensing/attribution does not itself resolve App Store duplication or template concerns.
- The actual Release274 AssistantSkills.framework contains MikaBundledSkills.json, byte-identical to source: **46,183 bytes**, SHA-256 `8ab9d90ac62642bebc191bcdfc9bbb72b8f0bb7ec3d6a8fe65a55d2c572f768a`.
- Its ten archived original documents are five skill files + three support files + LICENSE + NOTICE, with their source paths and hashes. Independently recomputed all ten hashes. Embedded LICENSE bytes equal root LICENSE and ios/licenses/Mika-Apache-2.0.txt (SHA-256 `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`). Attribution is packed inside JSON; no standalone NOTICE/LICENSE filename was found in the app, so do not describe those as separate copied bundle files.
- [ios/Sources/App/MikaAboutView.swift:133](../ios/Sources/App/MikaAboutView.swift:133) loads/displays that bundled license and upstream notice. [ios/Sources/AssistantSkills/BundledSkillCatalog.swift:105](../ios/Sources/AssistantSkills/BundledSkillCatalog.swift:105) pins the archive/source revision, checks hashes and separates original reference documents from iOS adaptations; original execution support is false.
- Actual embedded frameworks: **AssistantBrowser, AssistantContracts, AssistantDocuments, AssistantDomain, AssistantMCP, AssistantMemory, AssistantModels, AssistantPersistence, AssistantSkills**. These are repository targets, not nine independent third-party SDK products. Their names alone prove neither unique authorship nor functional uniqueness.
- Static linked Apple frameworks include SwiftUI, UIKit, Foundation, WebKit, PDFKit, CryptoKit, Security, Photos/PhotosUI, QuickLook, AVFAudio, Speech, AuthenticationServices, SafariServices, Network and UserNotifications. The target uses standard Apple capabilities but adds its own source-level workflows.
- No external Swift-package dependencies are declared by ios/Package.swift; no external vendor framework appeared in the inspected embedded inventory. Root Android dependency notices are not automatically an iOS SDK inventory. External user-selected AI/MCP services are service integrations, a different question from embedded code.
- Prompt provenance is mixed and explicitly documented: the skill archive pins upstream `0c172724...`; ChatOutcomeJudge cites upstream `964d7bec`; SkillLearningService cites `0c172724`; AISafetyRules identifies adapted Play safety/identity wording. Do not claim all prompts or skill content are WOOWTECH originals.

## Apporo iOS metadata — verified relationship signal, unresolved shipped-code comparison

Only relevant project metadata was read outside this repository. Two actual iOS project files were found:

1. [apporo-ios-1.0/ios/project.yml](/Users/woowtech/Projects/woowtech-mika-wt/apporo-ios-1.0/ios/project.yml:1): XcodeGen project name WoowAssistant; Swift 5 / iOS17; marketing 1.0.0, build1; app ID com.apporo.assistant; display name Apporo Assistant; eight named Assistant framework groups. SHA-256 `bfc696967a9328889092e02b413d1038d78ff27b8b3ef8ea1d8b4d1a0bfb9c96`.
2. [apporo-ios-1.0-b2/ios/project.yml](/Users/woowtech/Projects/woowtech-mika-wt/apporo-ios-1.0-b2/ios/project.yml:1): same app identity/named framework layout, marketing1.0.0/build2. SHA-256 `63bbaf96b14670acfd14edc3b09a5afd3b22baa3e64b7f360f96dae7640b004d`.

Both reference AssistantContracts, AssistantDomain, AssistantBrowser, AssistantModels, AssistantMCP, AssistantMemory, AssistantSkills and AssistantPersistence. Current WOOW's corresponding metadata adds AssistantDocuments and uses io.woowtech.assistant. Several top-level apporo-assistant directories inspected have Android project metadata and no top-level ios directory; that limited observation is not evidence that Apporo iOS source is absent elsewhere.

This confirms local related iOS project descriptions. It does **not** correlate either snapshot with Apple ID 6835318500's actual submitted binary, measure source or asset overlap, determine legal ownership, or prove a distinct end-user proposition. No other app's source bodies, images, screenshots, credentials, devices or account data were read. **Q5/Q6/Q7 remain owner gates.** Shared architecture and branding alone cannot substantiate an anti-duplication answer, and native/AI-assisted Swift is not by itself evidence of a commercial template.

## Owner facts needed before the final reply

Complete Q1–Q3's real audience/problem/comparison, identify actual external versus controlled-QA feedback for Q4, give the complete suite and consolidation rationale for Q5–Q6, establish shipped-version code/asset overlap for Q7, confirm development-service/template/artwork provenance for Q8, and identify the legal client/content provider/submitting relationship for Q9. Parent also resolves current ASC version/build alignment and working reviewer access.

Do not make categorical “all original,” “no shared code,” “no third party,” “not related to Apporo,” “all beta tests passed,” or “all commercial requirements passed” claims from this report. Technical implementation and licensing evidence support a candid answer; they do not substitute for the missing business and portfolio facts.
