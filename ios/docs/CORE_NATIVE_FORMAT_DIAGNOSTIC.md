# Manual core native format diagnostic — not a gate

`ios/.github/workflows/core-native-diagnostic.yml` is the iOS template. Run
`python3 ios/scripts/sync_monorepo_workflows.py` after edits and check the
resulting root workflow with `--check`. The generated workflow only has
`workflow_dispatch`. It cannot replace, feed or report a pass to the full
regression gate or the MCP-specific gate.

Two independent `macos-15` jobs build the selected checkout in Debug with Xcode
16.4 / iOS 18.5 and Xcode 26.2 / iOS 26.2. Each creates an owned disposable
simulator, prepares WebKit like the existing regression, enumerates seven core
targets and runs the same seven targets once. Enumeration and execution are
independent capture phases; a failed enumeration cannot be filled with test
log text. No UI or live-service workflow is selected. XCTest's actual raw
`discovery.json`, xcresult, xcresulttool summary/tests output, separate stderr,
exit statuses, toolchain/source metadata and product-tree fingerprints go into
per-version artifacts, including on failure where available. Products are not
uploaded. No fixture files from the Python test suite are uploaded as native
outputs. There is no mechanism for supplying an external discovery or result.

`manifest.json` always states `gate_eligible: false` and
`native_provenance_verified: false`. `capture_complete` means only that native
commands completed, nonempty JSON was obtained and the product fingerprints
matched; it is **not** a count, method, skip or result correctness check. An
xcresult containing a skip can still be collected. CI job success cannot be
used as proof of passing tests. No full-regression receipt is produced. The
native xcresult attempt tree and discovery syntax still require review against
the actual 16.4 and 26.2 artifacts before any gate adapter is enabled.

The workflow does not reference Actions secrets or variables, uses checkout
without persistent credentials, uses a fresh simulator, and invokes native
commands with a small environment allowlist that excludes GitHub/service
credentials and proxies. The selected core suites use synthetic fixtures,
including legitimate local loopback servers. This is **not an OS-enforced
network firewall**: simulator subprocesses/WebKit and future test changes
could access a network, and the bootstrap itself downloads pinned XcodeGen.
Review target sources and artifact content before running in any environment
with real accounts or sensitive data. Raw results and logs may contain fixture
values, paths and other diagnostic content; artifacts are retained for 7 days
and must not be treated as public-safe without review. Do not add real account
or service credentials to this diagnostic.

Each job has a 115-minute cap, so the conservative maximum is 230 combined
macOS runner-minutes per manual dispatch, plus artifact storage; parallel jobs
can finish sooner in wall time. Actual cost depends on runner billing and
artifact size. Current limits allow 45 minutes for build, 10 for simulator
setup, 50 for capture and 4 for cleanup, subject to the overall job limit.
Availability of the pinned Xcodes/runtimes, product layout, WebKit setup,
network fixtures and the exact tool output remain unverified until GitHub runs
the candidate. A timeout can leave incomplete evidence; it is never retried or
converted to success.

GitHub requires a workflow-dispatch file to exist on the repository's default
branch before it can be directly triggered; the new standalone workflow
cannot be directly dispatched while it exists only on the candidate branch.
The existing iOS workflow route below may provide an alternative. Do not assume
that an Xcode 27 capture proves either of the CI versions.

## Candidate-ref dispatch through existing iOS workflow

The candidate also adds the `core-format-diagnostic` choice to the existing
`ios-app.yml` dispatch input and calls this workflow from the **same commit**
via `workflow_call`. The seven ordinary targets run in the two fixed matrix
variants above; manual current/compact/large/fresh flags do not alter this
scope. It excludes the existing focused `build-and-test` job, full regression
and live jobs. It does not pass application secrets. GitHub still supplies its
normal read-only `GITHUB_TOKEN` to reusable workflows; checkout does not
persist it and native subprocesses receive the restricted environment.

The diagnostic dispatch receives a unique concurrency group incorporating
`github.run_id` and `github.run_attempt`, with a prefix distinct from all
current workflow groups. Different diagnostic runs therefore do not cancel
one another or normal regression runs. For other scopes the reformulated
expression preserves the prior group values and cancellation behavior.

Once this candidate ref is available on GitHub, use the *existing* `iOS`
workflow / root `.github/workflows/ios-app.yml`, select the exact candidate ref
and scope `core-format-diagnostic`. GitHub documents dispatching an existing
default-branch workflow on a selected ref, and that a local reusable-workflow
path resolves at the caller's commit. This route does not require the new
standalone diagnostic workflow to be present on the default branch. It remains
unverified whether this repository's UI and API will expose or accept a new
choice present only on the selected ref: the default branch still has the old
choice list. If GitHub rejects or hides it, do not choose `all`, `core` or a
live scope as a workaround; preserve the rejection and investigate without
running a different workload. Check the launched run's SHA, inputs, job names
and artifact manifests before treating the captures as this candidate's
actual evidence. No run is initiated by this change.
