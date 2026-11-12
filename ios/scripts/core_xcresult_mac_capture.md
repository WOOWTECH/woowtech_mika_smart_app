# MacBook: collect native discovery and xcresult format

This is an evidence-gathering recipe, not a gate. The paths, simulator UDID,
product origin and old result origin must be supplied by the operator; a
checkout's HEAD is **not** proof that an already-built product came from it.
The old iOS runtime version also does not establish which Xcode built the old
result. Xcode 27 parsing an older result is evidence of the Xcode 27 export
format only, not the behavior of Xcode 16.4 or 26.2.

## Privacy and side effects

Use a dedicated disposable simulator containing no accounts, credentials,
private data or real-service configuration, with external access disabled as
appropriate. `xcresulttool get` reads an existing bundle. Apple documents
`-enumerate-tests` as enumeration rather than execution of test methods, but
it can require the simulator and may load/launch test-host code; it is **not
proven to be side-effect-free or strictly read-only**. Do not run enumeration
against a personal or shared simulator. If isolation cannot be assured, run
only the xcresulttool exports and leave discovery uncollected.

The commands never print raw output. `umask 077` protects the temporary files;
raw JSON, stderr and xcresult can contain failure text, paths, user data, URLs,
identifiers or secrets. Keep them local and private, and do not upload or paste
raw files into an issue. The metadata may still include machine/build identity;
inspect all information before sharing even a redacted summary. No attachments,
logs, diagnostics or test method execution are requested.

## Commands

In a fresh shell, set the five variables to absolute local paths/values. Do
not paste credentials into them. The result may be any old xcresult; report
whether it is core or UI and its separately known originating CI run/version.

```sh
REPO='/absolute/path/to/source-checkout'
PRODUCTS='/absolute/path/to/existing/WoowAssistant.xctestproducts'
XCRESULT='/absolute/path/to/existing/Tests.xcresult'
SIMULATOR_UDID='00000000-0000-0000-0000-000000000000'
DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'
export DEVELOPER_DIR
umask 077
set -o pipefail
OUT="$(mktemp -d "${TMPDIR:-/tmp}/woow-xctest-format.XXXXXXXX")"
```

The following only reads the checkout and bundles, aside from private output
files. Tree hashes are tar-stream fingerprints for this machine/tool invocation;
they do not authenticate provenance or prove a clean source build.

```sh
xcodebuild -version > "$OUT/exporter-xcode-version.txt" 2> "$OUT/version.err"
git --no-optional-locks -C "$REPO" rev-parse HEAD > "$OUT/checkout-head.txt"
if test -z "$(git --no-optional-locks -C "$REPO" status --porcelain --untracked-files=all)"; then
  printf 'clean\n' > "$OUT/checkout-state.txt"
else
  printf 'dirty-or-untracked\n' > "$OUT/checkout-state.txt"
fi
printf '%s\n' 'product source/build Xcode and result source/build Xcode: independently verify; otherwise unknown' > "$OUT/provenance-note.txt"
(COPYFILE_DISABLE=1 tar -cf - -C "$(dirname "$PRODUCTS")" "$(basename "$PRODUCTS")" | shasum -a 256) > "$OUT/products-tar-sha256.txt"
(COPYFILE_DISABLE=1 tar -cf - -C "$(dirname "$XCRESULT")" "$(basename "$XCRESULT")" | shasum -a 256) > "$OUT/xcresult-tar-sha256.txt"
xcrun xcresulttool help get test-results tests > "$OUT/xcresulttool-tests-help.txt" 2> "$OUT/xcresulttool-help.err"
```

Check every command's exit status. If a hash or tool
command fails, record the failure and do not treat the output as complete.
Version/help and hashes describe the *exporter and files inspected now*.

Export the old xcresult, without running any tests:

```sh
if xcrun xcresulttool get test-results summary --path "$XCRESULT" > "$OUT/summary.json" 2> "$OUT/summary.err"; then
  printf '0\n' > "$OUT/summary.exit"
else
  printf '%s\n' "$?" > "$OUT/summary.exit"
fi
if xcrun xcresulttool get test-results tests --path "$XCRESULT" > "$OUT/tests.json" 2> "$OUT/tests.err"; then
  printf '0\n' > "$OUT/tests.exit"
else
  printf '%s\n' "$?" > "$OUT/tests.exit"
fi
```

Only on the dedicated disposable simulator, enumerate the seven core targets.
This performs no `test-without-building` execution action beyond enumeration,
though discovery may launch host code as described above. This operation is
not required to export the old result:

```sh
if env -i HOME="$HOME" PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
  TMPDIR="${TMPDIR:-/tmp}" DEVELOPER_DIR="$DEVELOPER_DIR" \
  xcodebuild test-without-building -testProductsPath "$PRODUCTS" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:AssistantDomainTests -only-testing:AssistantModelsTests \
  -only-testing:AssistantMCPTests -only-testing:AssistantMemoryTests \
  -only-testing:AssistantSkillsTests -only-testing:AssistantPersistenceTests \
  -only-testing:AssistantBrowserIntegrationTests \
  -enumerate-tests -test-enumeration-format json \
  -test-enumeration-output-path "$OUT/discovery.json" > "$OUT/discovery.log" 2>&1; then
  printf '0\n' > "$OUT/discovery.exit"
else
  printf '%s\n' "$?" > "$OUT/discovery.exit"
fi
```

Review locally before any sharing. For each file record only its command exit
status and whether nonempty; if suitable, privately share a deliberately
redacted, structurally faithful fixture containing no names, identifiers,
messages, URLs, paths, secrets or customer data. Retain distinctions between
missing, null, empty, repeated attempts and skip/failure. Do not fabricate a
passing native result. Indicate separately: current exporter Xcode/version,
known product build Xcode/version and source commit, old result producer
Xcode/version and CI run, destination runtime, and whether each is unknown.
Repeat on genuine 16.4 and 26.2 CI runners before claiming those formats are
supported.
