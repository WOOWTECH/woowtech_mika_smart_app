# Core XCTest evidence contract (integration pending)

This helper checks consistency of a **reviewed source inventory**, a claimed
native discovery list, and claimed per-test execution evidence. It does not
perform XCTest discovery or authenticate any artifact. Its successful output
always contains `native_provenance_verified: false`. Do not use
`contract_verified` alone as a native regression pass or release gate.

## Prepare a reviewed inventory

Run from the repository root, at the exact commit that will be built:

```sh
python3 ios/scripts/core_xctest_inventory.py template --root ios --output /tmp/core-inventory.json
```

The draft is deliberately invalid for verification. For each target, review
the declarations against its actual `project.yml` source membership, build
settings, generated sources, Swift compilation conditions, imports and SDK.
Set the exact Debug/Release profile, simulator platform, source commit and
condition flags. Record the reviewer and how conditions and inheritance were
checked. Populate `expected` with every applicable `Class/testMethod`; put an
inapplicable conditional declaration in `excluded` with its condition and
reason. Only declarations inside an `#if` region are eligible for exclusion.
Use separate reviewed inventories for different profiles when their tests differ.

The Swift scan is **not the compiler or native discovery**. It is a conservative
review aid, not an authoritative inventory: the reviewer must inspect all
sources and evaluate conditions, including `canImport`, OS and architecture.
It rejects known unsupported inheritance, test extensions, Swift Testing,
unknown class bases, several unsupported project/source forms, symlinks, and
external project includes/config files/build scripts. It does not understand
all Swift or XcodeGen syntax and cannot prove that the review is complete.
Unrecognized syntax and inherited/generated tests must be resolved by a
compiler/native-aware adapter before treating the inventory as complete; do
not add exclusions merely to make a mismatch pass. A new project format,
target, base class or source selection needs explicit review and support.

The snapshot hashes `project.yml` and all files selected by the supported test
target `sources`, including hosted test sources outside the test directories.
It does not hash the complete application tree, SDK, tools, environment, or
external build inputs. The helper checks `source_commit` against checkout HEAD,
but does not prove the checkout is clean, that the product was built from it,
or that profile and reviewer claims are correct.

## Adapter contract

A future trusted CI adapter must independently discover methods **from the
actual built XCTest products** for the exact destination/configuration, without
using the source scan or execution results as its discovery list. It must fail
closed on incomplete discovery, unknown identifiers, unsupported enumeration,
missing targets, unavailable artifacts, and mismatched build/run provenance.
It must establish the clean checkout, Xcode/SDK, full build settings, conditions,
destination, product and XCResult/log provenance, and that discovery and
execution use the same product. Preserve the original artifacts. Discovery and
execution evidence must cover the entire intended run, including all attempts;
no filters, retry aggregation, or log truncation may hide a failed/duplicate
attempt. The helper itself cannot establish any of these properties.

Normalize evidence as UTF-8 JSON with unique keys. `snapshot_sha256` is the
inventory snapshot's `sha256`; `product_sha256` is the SHA-256 of the exact
product archive passed to the helper. `profile` must equal the inventory's
profile. Identities use `Target/Class/testMethod` (Swift module must match the
target; unsupported identities must fail rather than be silently renamed).

* Discovery: `schema: "core-xctest-discovery-v1"`, `complete: true`,
  `snapshot_sha256`, `product_sha256`, `profile`, and unique `tests` identities.
* Execution: `schema: "core-xctest-execution-v1"`, the same three binding
  fields, nonempty `run_id`, `destination`, `runtime`, and SHA-256 fields
  `discovery_sha256`, `summary_sha256`, `log_sha256`. The first two hash the
  helper's `canonical()` encoding of the normalized objects; the last hashes
  the exact UTF-8 log text supplied to `verify`.
* Summary: `result: "Passed"` and integer `totalTestCount`, `passedTests`,
  `failedTests`, `skippedTests`, `expectedFailures`, from the complete run.
* Log: complete XCTest `Test Case '-[Target.Class testMethod]' started.` and
  `passed (...)` lines. Every expected identity must have exactly that pair,
  in order; unknown, missing, repeated, failed, skipped or unrecognized test
  events reject the evidence. Unsupported native log formats require an
  independently validated adapter, not relaxed matching.

```sh
python3 ios/scripts/core_xctest_inventory.py verify --root ios \
  --inventory /tmp/core-inventory.json --discovery /tmp/core-discovery.json \
  --execution /tmp/core-execution.json --summary /tmp/core-summary.json \
  --log /tmp/core-run.log --product /tmp/core-products.zip
```

The adapter must require successful trusted provenance verification **and** a
successful helper contract, and independently fail the job on either failure.
The adapter and provenance verification do not exist in this change. This
contract therefore cannot yet satisfy a native gate. In particular, fabricated
JSON, a fake product, and a matching synthetic log can pass consistency checks.
Test this limitation and the actual native identifier/log formats with real
Xcode artifacts before integration. The separate iPad UI full-plan inventory
and its native verification also remain out of scope.

Run synthetic contract regressions with:

```sh
cd ios/scripts
python3 -m unittest -v test_core_xctest_inventory
```
