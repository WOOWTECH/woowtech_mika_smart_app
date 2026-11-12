# Native core XCTest evidence capture: diagnostic only

This is an adapter-in-progress, **not a CI pass gate**. It calls Apple's tools,
retains their raw evidence and rejects known bad xcresult summaries. It always
exits nonzero even after successful tool calls: we have not verified the actual
native discovery JSON and per-test xcresult structures for this repo on either
CI Xcode version, nor proved product/build provenance. It does not write a
pass receipt or feed fabricated data to `core_xctest_inventory.py`.

Apple documents `xcodebuild test-without-building -enumerate-tests
-testProductsPath ...` in the Xcode 15 release notes, and the `xcresulttool get
test-results summary` and `tests` commands in the Xcode 16.3 release notes:

* https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes/
* https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes

The repository's `.github/workflows/ios-app.yml` creates one portable
`.xctestproducts` bundle per Xcode, transfers it with a source-commit file and
checksum, then executes one core slice on each selected simulator.
`ci_full_regression.py` uses seven target selectors, a single execution and
`-parallel-testing-enabled NO`. This standalone capture mirrors those selectors
for an independently scheduled diagnostic run. It does not modify or replace
that workflow, existing core gate, or the MCP-specific gate.

## Diagnostic invocation on a disposable CI simulator

After CI has built, transferred, checked and prepared the products exactly as
in the existing workflow, with a clean checkout and a booted dedicated iOS
simulator, call the following. The output directory must not already exist and
must be outside the checkout and products:

```sh
python3 ios/scripts/capture_core_xctest_native.py \
  --root "$PWD" --products "$PWD/ios/build/WoowAssistant.xctestproducts" \
  --simulator-id "$SIMULATOR_UDID" --output /tmp/core-native-diagnostic-unique
```

The expected nonzero status must **not** be ignored by a real gate; a separate
non-gating evidence collection job can save the output on failure. Keep the
raw enumeration, version and test logs, `Tests.xcresult`, xcresulttool summary
and tests JSON, and context together. They may contain test data: follow the
existing artifact handling rules. Never publish artificial fixtures as native
outputs. Preserve exact bytes.

The tool checks the checkout for tracked/untracked changes, records its HEAD,
hashes the product directory tree before and after discovery and execution,
checks the process exits, and checks a subset of the actual xcresult summary
shape observed in the repo's retained CI artifact: successful overall result,
nonzero all-passed counts, no skip/failure/expected failure, exactly one
matching iOS Simulator destination with consistent counts. Nonmatching or
unknown summaries fail closed. It does **not** parse the xcresult test tree or
native discovery payload, prove each method ran once, verify version support,
prove the product was built from the checkout, or authenticate downloaded build
artifacts. Git-ignored source inputs and toolchain/build flags are not covered
by the clean-checkout check. Snapshot hashes do not prevent concurrent
modification followed by restoration. A symlink escaping the product bundle is
rejected. These checks are only diagnostics and cannot establish a gate pass.

Tests can print arbitrary text that resembles an XCTest log. Such output is
untrusted and must not be promoted to per-test native proof. A future adapter
must consume genuine, complete xcresult test/attempt data directly from
`xcresulttool` and compare it to independent discovery from the exact built
product, including all relevant compilation conditions and inherited methods.
It must reject missing/duplicate/retried/skipped cases, unknown output forms,
nonzero process exits, mismatched destination/profile, and unverifiable build
provenance. Confirm that `-enumerate-tests` selectors do not hide tests via the
scheme or test plan, and cross-check reviewed source inventory against real
compiler/native discovery. Validate real output and adversarial fixtures on
both Xcode 16.4 and 26.2 before removing the unconditional failure or
connecting any release gate. No iPad native verification is implied.

Run the synthetic tests with `cd ios/scripts && python3 -m unittest -v
test_capture_core_xctest_native test_core_xctest_inventory`. Synthetic successes
prove only rejection/contract logic, never a native test pass.
