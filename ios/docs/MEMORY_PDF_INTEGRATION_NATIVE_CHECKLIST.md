# Memory lease and PDF search: native validation checklist

This is a plan for the commit containing this file, not a native test result.
MacBook and GitHub iOS simulator runs may proceed in parallel. Record the exact
commit, Xcode and simulator runtime, destinations, result bundles, counts,
failures and skips. Use only synthetic fixtures; do not supply real model, MCP
or worker credentials. This task does not authorize physical iPad setup or use.

## Targeted native tests

From `ios/`, generate the project and run against an available iOS simulator;
replace the placeholder with its UUID. The fixture UI test must use the actual
encrypted-store lease, not bypass the lease or manually fake a busy response.

```sh
make project
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -resultBundlePath build/memory-pdf-targeted.xcresult \
  -only-testing:AssistantSkillsTests/ProfileChatAppIntegrationTests/testChatContextDispatchFences \
  -only-testing:AssistantSkillsTests/ProfileChatAppIntegrationTests/testMCPExecutorDispatchFences \
  -only-testing:AssistantSkillsTests/DocumentQueryTests/testBoundedPatternSearch \
  -only-testing:AssistantSkillsTests/DocumentQueryTests/testModelLineOffsetsAndWhitespace \
  -only-testing:AssistantSkillsTests/DocumentQueryTests/testModelWorkerCancellation \
  -only-testing:AssistantSkillsTests/DocumentQueryTests/testApprovedPDFModelPatternRoundtrip \
  -only-testing:AssistantSkillsTests/DocumentQueryAppIntegrationTests/testPatternSearchWithMemoryReferences \
  -only-testing:WoowAssistantUITests/MCPConversationUITests/testMemorySwitchReportsBusyAndRetriesAfterActualMCPLease \
  -only-testing:WoowAssistantUITests/SkillExecutionUITests/testOfflineSearchUsesApprovedExtractionAndClearsEditedResults \
  -only-testing:WoowAssistantUITests/SkillExecutionUITests/testOfflineSearchCanIgnoreEnglishCaseAfterApproval \
  -only-testing:WoowAssistantUITests/SkillExecutionUITests/testOfflineLimitedPatternSearchUsesApprovedPDF test
```

Confirm the actual executed selectors rather than assuming that a successful
build ran them. The busy UI case holds the real lease through a synthetic MCP
executor, verifies the failure alert and unchanged on switch, releases the
executor, retries, and checks persistence after relaunch. The PDF cases verify
separate approvals, case sensitivity, pattern validation and stale result
clearing on a synthetic PDF. The core cases also cover bounded model pattern search, match offsets, cancellation and an authorized snapshot. The App integration case covers the model pattern command with captured memory and revocation using a synthetic client; it is not an arbitrary workspace.

## Full simulator coverage and manual checks

- Run the preserved `ios-app.yml` full non-Live regression for this exact
  commit. Its planned matrix includes three iPhones and an iPad simulator;
  `ui-mcp` owns the busy UI case and `ui-documents` owns the PDF UI cases.
  Preserve each shard's results and check the aggregate for missing/skipped
  tests. The iOS 17 release workflow separately owns the `documents-read`,
  `documents-output`, `documents-chat`, and `ui-mcp` selections.
- On a simulator, inspect memory failure/retry text and switch state in all
  three supported languages and with VoiceOver/accessibility enabled. Inspect
  PDF approval, pattern help, errors, cancel/stop, result invalidation,
  accessibility and scrolling on compact and large layouts. Automated UI
  cases listed above currently exercise Traditional Chinese, not all languages
  or VoiceOver.
- Exercise cancel/failure and multi-round MCP fences with synthetic transports;
  verify the review and executor use the current context. The separate plan in
  `CHAT_CONTEXT_NATIVE_VALIDATION.md` describes the still-unimplemented genuine
  two-window case and its scene-availability prerequisite.
- Validate PDFKit extraction, native picker and responsiveness with local
  synthetic PDF files, including repeated pages and the documented bounds;
  do not infer parser memory/time guarantees from the bounded search algorithm.
- Run an iPhoneOS Debug and Release build for the same commit and verify the
  DEBUG-only fixture is absent from Release. Record build and test results
  independently. Live model/MCP workflows remain subject to their existing
  branch and authorization restrictions and are outside this synthetic plan.

The coordinated lock only covers participating store instances; older or
non-cooperating writers are outside its guarantee, and data already dispatched
cannot be recalled. Memory may remain enabled while a lease is held, requiring
the user to retry. PDF search is restricted to an approved extraction snapshot,
a documented bounded regex subset and ASCII case folding: it is not Android's
full Java-regex workspace search. See `SKILL_RUNTIME.md` for exact limits.
