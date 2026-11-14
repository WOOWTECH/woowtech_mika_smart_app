# Skills execution increment

This increment provides actual selected-file PDF execution. It does not execute arbitrary Markdown, add Python to iOS, or claim parity with Mika's six original skills. Phone and other native-App automation remain excluded. No remote service, cloud resource or credential is created by this increment. App integration is committed in `a74df45`; simulator validation is recorded in VERIFICATION.md as results arrive.

## Querying an extracted PDF

### Limited regular expressions over an approved PDF snapshot

The offline search offers a separate, default-off limited pattern mode. It
supports Unicode literal scalars, `.` (one scalar), ASCII `\d`, `\w`, `\s`
(space, tab, vertical tab or form feed within a line), literal/range classes such as `[A-Z0-9]`, Unicode scalar
classes, negated classes such as `[^0-9]`, greedy `+` and `*`, exact repeats
`{n}` for 1–16, and backslash-escaped metacharacters. Classes may contain up
to 16 literals or ranges; inside a class, escape `]`, `-`, `[` or `\` as
needed. Class shortcuts such as `[\d]` are not implemented. The A–Z case
option applies only to ASCII letters, including class ranges; Unicode
normalization and non-ASCII case folding are not performed. As in Java's default
mode, `.` excludes CR, LF, U+0085, U+2028 and U+2029. Matching is greedy,
non-overlapping, and cannot cross CR or LF; UTF-8 offsets, bounded snippets,
original page and selection index all refer to the unchanged snapshot.

**Only nonempty matches are shown.** For a nullable pattern such as `a*`, empty
matches are deliberately skipped and a scalar is advanced, preventing infinite
loops. This differs from Java's complete match list and is stated in the UI.
Empty/malformed expressions are reported separately from unsupported syntax.
Groups, alternation, anchors, `?`, lazy/possessive quantifiers, variable
`{m,n}`, backreferences, class intersection (`&&`), Unicode property classes
and class shortcuts remain unsupported and are never passed
to a backtracking engine or silently treated as literals.

The implementation uses dynamic programming, processing each input scalar once
per compiled term, with at most 64 terms and 16 ranges per class. Its work is
linear in input length for this fixed bounded syntax, not exponential
backtracking. Patterns are capped at 256 UTF-8 bytes; each page at 262,144
Unicode scalars; and each search at 5,000,000 work steps. Four compact arrays
need about 4 MiB at the per-page ceiling, in addition to the approved snapshot
and normal object overhead. A bound reached is an error, not a no-match or
partial success. At most 20 matches are returned with a truncation indicator
only if another nonempty match exists. Match snippets are limited to 320 UTF-8
bytes even for a long match. The background task checks cancellation at least
every 1,024 work steps and the App offers Stop. Editing the input, changing
mode or case, replacing the source, or leaving the view invalidates pending
results. Query edits compare UTF-8 bytes, so switching between canonically
equivalent composed and decomposed spellings updates the actual query. A worker returning after cancellation cannot publish to the screen.

Android `search_files` instead supports Java regular expressions and scans
workspace lines with its own 10-second deadline and 100-line match limit. The
iOS subset is not full Java regex or workspace parity, does not invoke a model,
external PDF worker or network, and does not create read/citation receipts.
Native iOS UI, memory and device responsiveness remain revision-specific
acceptance checks.

Android's `documents/SKILL.md` names `search_files` for extracted text. The
Android sandbox compiles its `pattern` with Kotlin `Regex`, so `(?i)budget`
matches an ASCII case variant such as `BUDGET`. This local iOS option supports
that narrow case-insensitive literal use; the separate limited pattern mode is
explicitly selected by the user. It operates only on the immutable, approved PDF text
snapshot, returns original bytes and page/selection numbers, and neither runs a
worker nor sends data. General regular expressions, arbitrary workspace files,
and full Android execution parity remain unsupported by this option.


The completed extraction also offers a separate local literal-text search. The
user explicitly starts it on the already approved snapshot; it uses no model,
worker, network or additional file read. It shows original page numbers and
selection indices (including repeated pages), up to 20 matches and a truncation
notice. Editing the term or changing its case option clears old results and
invalid terms show an error. An explicit, default-off option matches ASCII A–Z
without case; all other UTF-8 bytes remain exact, with no Unicode normalization.
The search operates on extracted selected pages; it does not supply OCR or
Android's arbitrary workspace/full-regex search. The snippets can contain
document text and should be treated as sensitive on screen. Search controls,
results and errors use the selected Traditional Chinese or English interface
language; extracted snippets remain verbatim. Other parts of
the PDF skill screen are not yet fully localized. Native iOS UI acceptance is
still required.

The PDF extraction result now offers a separate query sheet. It receives the completed `SkillExecutionPDFResult` directly; it does not parse page-marker prose or reopen a file. The immutable snapshot binds the original PDF hash, extraction engine, pinned original provenance and ordered selected pages. Repeated selections of one original page retain separate one-based selection indices and their original page numbers.

The user enters a question, reviews the currently configured model destination, then explicitly starts. The model receives the question and source manifest. The original `search_files(query, limit)` remains a case-sensitive literal search; `search_files(pattern, path?, glob?)` adds Android-like one-result-per-line matching over the approved snapshot only. It is wired into this PDF query runner, not generic chat or a filesystem workspace. `/workspace/approved-document.txt` is a synthetic name, never opened on disk; `path` accepts only `/workspace`, `/workspace/`, or that exact name. The optional ASCII glob supports basename literals, `*`, `?`, and an optional `**/` prefix. Other paths or glob syntax return explicit errors, not empty matches. The pre-existing source and destination approvals remain in force, with no new confirmation.

Pattern search uses the same bounded subset described above, case-sensitive, with no arbitrary Java regex or inline `(?i)`. Unlike the offline occurrence UI, a nullable pattern counts an empty match, as Android's per-line predicate does. It reports at most 20 matching lines, each clipped to 300 UTF-8 bytes with `textTruncated`, and a result-level `truncated` flag if more matching lines exist. Line numbers describe selected page occurrences in order with a synthetic newline between pages, including blank trailing lines. Page index, original page number and UTF-8 line-start `offset` are retained; `matchOffset` and `matchLength` give the first (leftmost, greedy) match as page-relative UTF-8 bytes, allowing a separate read even when the line prefix was clipped. Nullable patterns can return a zero-length match; that location alone is not textual evidence. The 262,144-scalar page and 5,000,000-step limits, cancellation, and overall deadline apply; errors discard partial output. Android searches actual workspace files, returns up to 100 lines and uses Java regex and filesystem glob rules; this is a narrower interface and behavior, not full parity.

The model can also issue `read_file(pageIndex, offset, limit)`, `finish(answer, citations)` or `refuse(reason)`. Reads return at most 8192 UTF-8 bytes, preserving character boundaries and an actual read ID. Search snippets do not enter the read ledger. Every final citation must match bytes inside an actual read; page labels are supplied by the host. These checks prove quotation provenance, not semantic correctness or full-document coverage.

The runner shares twelve model calls and a 180-second overall deadline, including model waits, with at most one syntax correction. Source text remains bounded to 2 MiB; tool/context/reply sizes are also capped. It holds no file, URL, shell, worker, messaging or approval capability. Original skill prose is data, not execution permission. Cancellation, changing the question or model configuration prevents late publication; completed answers survive a later configuration change. No memory or skill is created by this flow.

The completed answer and verified page citations can be exported through the native destination picker using an immutable UTF-8 FileDocument. Only the exporter success callback reports a saved file; cancellation preserves the answer. Closing the query sheet retains the extraction. Core, App, real-model and native UI validation are tracked separately in VERIFICATION.md; adding this entry point alone is not an acceptance result or full original workspace parity.

## PDF page assembly

`SkillPDFAssemblyView` is available from the documents catalog. It uses `SkillPDFAssemblyRuntime` with 1–3 actual native-picker selections, individual one-use read approvals, immutable snapshots and an explicitly reviewed output order such as `1:3,1:1-2,2:1`. The output order can interleave files and repeat pages. Updating the selection or clearing the screen cancels the old runtime; the App generation and reviewed-text guards prevent stale results or plans from being published. The native FileDocument exporter receives only completed immutable bytes and asks for a destination; replacing an existing destination requires the system's explicit user confirmation.

The limits are 10 MiB per source, 30 MiB aggregate bytes, 200 aggregate input pages, 200 output pages and 20 MiB accepted serialized output. Static unencrypted pages only: forms, annotations, attachments, outlines, tagged structures, optional-content layers and interactive relationships are rejected. PDFKit normalizes page origins; dimensions and media-relative boxes use a finite four-ULP comparison after an actual fractional roundtrip exposed a 1.1368683772161603e-13-point difference with identical rendered pixels. Rotation remains exact. Serialization cannot be forcibly interrupted or assigned a hard peak-memory limit; cancellation prevents late publication and the byte limit is checked after serialization. This is a native adapter, not generic original `run_command`/pypdf execution.

Local core: `python3 scripts/check_pdf_assembly.py` executes 284 assertions, including raster/text/page geometry, actual coordinated reads, review grants and cancellation races. [App evidence](evidence/pdf-assembly-app-local.json) covers unchanged production Session and FileDocument, real disk export/readback and cancellation during a held coordinated read: 57 assertions per Debug/Release local configuration. These are macOS checks; the actual native picker/review/assembly/export-cancel case is a separate iOS acceptance requirement.

## Integration contract

The App presents `SkillExecutionView(learning:modelAccess:modelChanges:)` from both the Skills page and the `documents` catalog detail inside the existing NavigationStack. This view owns its file importer, options, review, per-step authorization, cancellation and text results. Extraction always uses native PDFKit and does not require a model, MCP connection or API key; only the separate optional query uses model access. The optional original-script worker and its 腳本服務 settings were removed on 2026-11-13 to match the Play build. Do not label the bundled skills executable on account of this entry point.

The callable core lives in `Sources/AssistantSkills/SkillExecution*.swift`:

```swift
// Only construct this from the actual document-picker/fileImporter callback.
let selection = try SkillExecutionSelectedFile(userSelectedURL: url)
let options = try SkillExecutionPDFOptions(pages: "1,3-5", metadataOnly: false)
let runtime = try SkillExecutionRuntime(
    selectedFile: selection, options: options,
    catalog: BundledSkillCatalog.bundled())
let plan = runtime.plan
// Display plan.filename, pages, metadataOnly, includesPassword, fingerprint,
// steps' disclosures/availability and provenance before asking for execution.
// For EACH explicit user approval, on that exact runtime:
let approval = try await runtime.authorize(stepID: step.id)
let result = try await runtime.execute(approval)
// .selectedFileRead(byteCount:sha256:) or .pdf(SkillExecutionPDFResult)
// await runtime.nextStep() returns the next reviewable step, or nil.
// await runtime.cancel() invalidates remaining grants and drops the snapshot.
```

`SkillExecutionRuntime` has two separately approved steps: read one selected file into an immutable bounded snapshot; then extract it on the device with PDFKit. Nothing is uploaded. Each grant is opaque, in-memory, bound to the exact runtime/plan/step, expires after 120 seconds, and is consumed before attempting an effect. Failed attempts require a new grant. Changed inputs require a new runtime. Cancellation discards late results; the supplied view also cancels its executing `Task`.

Plans and grants have no public deserialization path. Plan fingerprints cover selection identity, filename, options (password presence only), destination, capability availability, disclosures, step IDs, source paths/revision/hashes. Runtime IDs prevent a grant from one plan being replayed in another. `authorize` is a **trusted UI/orchestrator boundary**, not a model tool. Do not expose it or `SkillExecutionSelectedFile(userSelectedURL:)` to model-supplied URLs or text. Import approval, active/trial status, reference prose and original instructions do not grant execution permission.

`SkillExecutionDependencies.reports(catalog:)` returns all five reviewed dependency reports with source hashes. `hostIntegrationRequired` identifies an existing lower-level path, not a registered or executable runtime operation.

## Pinned original evidence

Repository: <https://github.com/wangzan101/Mika>, revision `0c172724f3f0c96f7345262588072f6e95db1138`, inspected locally at `/tmp/woow-mika-memory-reference`. All six instructions and all three supporting assets were read. Paths below are relative to `core/src/main/resources/skills/`. Since 2026-11-13 the iOS catalog bundles five of them: `configure-mika` is left out to match the Play build, where the model cannot change settings.

| Source | SHA-256 |
| --- | --- |
| `configure-mika/SKILL.md` | `25560ad126c10263f0c341dd5d25d5e12fe4335a372abe7b8d08895725d97c4f` |
| `content-transcribe/SKILL.md` | `fa46715f63de39a274d877f4cc5ec347fb639d7a5bb9aeb8f8b0f81fcf352326` |
| `content-transcribe/references/transcript-output-formats.md` | `bbd7bb15518ecf353d1b26ed8c25a24ee471d0bc7a6dc510b8f8a6153d2dc9e8` |
| `documents/SKILL.md` | `f5cfa97a04bab6fcbfba4b654c9a59018dd339eea83b260ace47928e3abf230c` |
| `documents/scripts/extract_pdf.py` | `41c2e2b51cd23173e0891084d0cd93d54e300e5fd571876740de36ac5968817c` |
| `documents/scripts/manifest.json` | `010bf7bf1102f06e20b29b8b63e0ceedf5b7e6856cb76f67ae8f9e2fa74515cf` |
| `info-research/SKILL.md` | `75f1bd627136a4e022625f7701fef19f07665b0b52718e0f524997cbf61129c2` |
| `messaging/SKILL.md` | `030ef07f6708cea769889a039ee7fcaf8ec3d036032692b83006dc84d99886c9` |
| `skill-authoring/SKILL.md` | `2ca1e847565726ec25b55908e3ecd00d1750664638f8c327d699234ecea37a42` |

The existing catalog verifies its whole resource and individual document hashes. Execution builds provenance from that verified catalog. The original script and manifest stay in that catalog as inert text; nothing runs them.

| Original skill / actual dependency | Existing iOS mapping and this increment's boundary |
| --- | --- |
| configure-mika: `settings_list`, `settings_set` | Not bundled and not mapped (owner decision 2026-11-13, matching the Play build). No model tool can list or change App settings; the appearance is chosen only in Settings › 語言與外觀. |
| content-transcribe: `web_read_page`, `read_file` in `/workspace/inbox/`, format reference | The separate TranscriptRuntime now consumes an explicitly approved native UTF-8 file or rendered-text webpage snapshot, with bounded chunked reads, five output formats and exact source citations. The complete original format reference is retained. Actual-model formatting and native picker acceptance are recorded per revision, including preserved failures, in CONTENT_TRANSCRIBE.md and VERIFICATION.md. No speech-to-text upstream or here. |
| documents: `web_navigate`, `web_downloads`, `/workspace/inbox`, `/workspace/downloads` | Existing browser navigation/download work is separate. This runtime accepts only a selected PDF, never a workspace path or directory enumeration. A browser-download owner may offer its file through an explicit user selection flow. |
| documents: `run_bundled_script`, `source=skills/documents`, `scripts/extract_pdf.py` | Native PDFKit actual text/selected pages/metadata/unlock path, the only PDF path: the opt-in original Python worker was removed on 2026-11-13 to match the Play build. Results identify PDFKit and never carry a claim of having run Python. |
| documents: `--out`, `read_file`, `search_files`, `share_file` | Query runner reads/searches only one completed approved PDF text snapshot, with actual-read citations and original page numbers. Native fileExporter delivers extracted text or the completed answer to a user-selected destination. The complete real-model query, citation and export-cancellation UI case passed 1/1 on iOS 18.5 at `ae381fc`; exact iOS 17 acceptance is separate. No arbitrary workspace, automatic external send or model-selected destination. |
| documents: `run_command` + pypdf split/merge/extract pages | Native PDFKit adapter supports reviewed static-page extraction/reordering/merging and explicit output export. Arbitrary shell/Python is not available locally; this is not generic pypdf execution. OCR is absent upstream and here. |
| info-research: `web_navigate` search pages, `web_read_page`, Android app search, independent sources and dates | Same-origin research, search-engine source discovery with manual selection, and separately approved 2–3-root multi-source research are implemented. Actual observations and exact citations are checked; selecting search results does not start research. Model-autonomous query reformulation and blanket publisher-independence claims remain unavailable. Native-App search is outside the agreed scope. Latest native/live acceptance is revision-specific. |
| messaging: open account/thread, inspect recipient/body, send and verify | Existing `MCPSession.conversationConnection()` and `MCPConversationRunner` support discovery/selected tools/per-call approval. No messaging tool/account is assumed; this runtime does not register a send capability. Original prose saying not to ask again cannot grant authorization. |
| skill-authoring: `skill_search`, `skill_read`, `ask_user`, `skill_save(markdown, quote, version)` | Manual and model-driven App flows use `SkillAuthoringBridge` plus `SkillToolSession` for actual search/read/clarification/prepare, followed by full user review and an atomic encrypted commit through LearningStore. Existing reads, exact request text, current generation and capabilities are checked before storing a trial skill. The model cannot approve or commit its own proposal. Real-model acceptance at `6d480d8` passed 1/1; this approval grants no tool-execution permission. |

The only original executable asset among the six skills is `extract_pdf.py`. Its manifest is exactly `[{"file":"scripts/extract_pdf.py","runnable":true,"needs":["apk:py3-pypdf"]}]` (whitespace omitted here). It imports Python stdlib `argparse`, `json`, `logging`, `os`, `sys`, and dynamically imports `pypdf.PdfReader` and `pypdf.errors.PdfReadError`. Upstream does **not** pin a Python or pypdf version. iOS does not run it; PDFKit replaces it.

Original arguments: input path, `--pages` (1-based ranges preserving order/duplicates), `--metadata`, `--out`, `--password`. Original exit 2 means failure; exit 3 means all selected pages have no extractable text. The native path keeps the same page selection rules and reports empty pages explicitly; there is no arbitrary filesystem write option.

## Native PDF behavior

The first approved step opens security-scoped access for the selected URL, coordinates access with NSFileCoordinator, rejects directories/symlinks/non-PDF/oversized inputs, bounds the actual read after provider coordination, and balances scope release on success/failure. The snapshot is in memory only; the second step does not reopen a changed file. The supplied selection API is trusted app code; it is not a replacement for Apple's document picker sandbox authorization.

Maximum file size is 10 MiB, maximum selected page count 200, text/metadata output 2 MiB. One-based ranges retain explicit order/duplicates; malformed/empty components and out-of-range pages fail. Metadata-only mode does not read all page text. Password is transient, excluded from plans/hashes, and never logged. Results retain original page numbers, empty-page notices and input SHA-256. Empty text is reported as possibly requiring OCR; it is not asserted to prove an image scan. PDFKit reading-order differences, tables, columns and unsupported/damaged PDFs remain limitations. PDFKit has no hard per-page CPU/memory preemption here: file/page/output limits bound input and returned data, not all parser internal allocation/time. Cancellation is checked between pages and before publishing results.

Apple behavior consulted: [fileImporter security-scoped access](https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)), [balanced URL access](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()), [PDFDocument from Data](https://developer.apple.com/documentation/pdfkit/pdfdocument/init(data:)), [PDFPage text](https://developer.apple.com/documentation/pdfkit/pdfpage/string), [password unlock](https://developer.apple.com/documentation/pdfkit/pdfdocument/unlock(withpassword:)), and [PDF write options for encrypted test fixtures](https://developer.apple.com/documentation/pdfkit/pdfdocumentwriteoption).

## Removed: original-script worker

Owner decision (2026-11-13): iOS-only features go, to match the Play build. The
optional original-script worker is gone: the 腳本服務 settings and their entry on
the PDF screen, the Swift HTTP client, the runtime's upload step, the worker
container (`scripts/skill-worker`) and its CI workflow. PDFKit on the device is the
only PDF path. Settings saved by older builds (defaults suite
`io.woowtech.assistant.skillworker.v1` and its Keychain item) are no longer read;
clearing that Keychain item is handled separately. Earlier worker evidence stays
in [VERIFICATION.md](VERIFICATION.md).

## Repeatable validation

The iOS Skills XCTest target is hosted by the actual WoowAssistant App as of
`2dd7b69`, with generated `TEST_HOST`/`BUNDLE_LOADER` verified in Debug and Release.
The earlier unhosted coordinated-file test reached PDFKit and stalled in a system
process wait. Without changing its assertions or the PDF reader, the hosted SE
18.5 and iPhone 17 / 26.2 runs each passed all 34 selected skill, memory and
persistence cases; the coordinated-read case took 0.089/0.091 seconds. Separate
native picker runs passed the full PDF selection/extraction flow, while earlier
FileProvider bookmark failures and native export failures remain unresolved.
This corrects the XCTest execution context; it is not proof of a production
PDFKit fix, full original-skill parity or iOS 17 UI acceptance. Run URLs and
revision-specific failures are retained in [VERIFICATION.md](VERIFICATION.md).

On macOS CLT Swift 5.8, use the exact same assertions as the new XCTest file via its standalone mode:

```sh
bash scripts/check_skill_execution.sh
```

The Swift checker covers real PDFKit text/metadata/page ranges/order/duplicates, empty text, actual encrypted PDF generation/unlock, malformed/oversized files, scope selection boundary, immutable byte snapshots, grant forgery/replay/wrong-plan/expiry and cancellation.

Local evidence: Swift core typecheck and standalone PDFKit tests passed. `swift build --target AssistantSkills` was attempted and failed before compilation because this CLT installation lacks Xcode SDK `PlatformPath`. Full SwiftPM/XCTest/iOS compilation and file-provider UI behavior require the parent's authorized Xcode CI. SwiftUI file syntax parsing is not an iOS build. The integrated parent workflow now exercises the actual native Files picker; results must be read from that run, not attributed to earlier CI runs.

The completed native result can be exported as bounded UTF-8 plain text through the system destination picker. Its immutable FileDocument is separate from the execution runtime; cancellation keeps the extraction result, and a late callback cannot update a replaced plan. Export serialization is tested with actual file write/readback; native picker save/cancel acceptance is recorded per simulator run.
