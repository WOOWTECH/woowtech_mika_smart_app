# Cloud startup smoke

`apporo.yml` retains PR/workflow_dispatch triggers and existing build/contracts.
The build's combined debug+release invocation enables ABI splits, so the new
single-APK artifact explicitly selects `*universal-debug.apk` (debug signing,
no release key). It avoids downloading every release/ABI APK; it does not strip
runtime assets or promise a fixed compressed size.

Four dependent Ubuntu24.04 jobs run official AOSP `default` **x86_64** images API30 (minSdk),
32 (legacy permission boundary), 35 (targetSdk), 36. This samples API startup,
**not permission-flow coverage or an ABI matrix**. ARM64/helper/sandbox/model
functionality remains with the existing device runner. Startup code calls
RuntimePreparer; SandboxState rejects non-arm64 ABIs. Google APIs x86_64 images advertise translated arm64 in the official API30/35
build properties, so they can trigger that automatic preparation even without
UI actions. To honor the no-sandbox scope, use AOSP `default` images instead of
the suggested Google APIs images. All four exact packages were found in the
official repository index on 2026-11-08. The smoke also refuses any image
advertising arm64 translation before installing/starting the app. Actual
booted ABI properties still require first CI confirmation; no GMS parity claim.

The script requires Linux + GITHUB_ACTIONS=true, accessible KVM and no existing
ADB devices. Do not run it against local devices. Only CI invokes:

```sh
python3 apporo/tools/startup-smoke.py --api 30 --apk startup-apk --out startup-evidence
```

SDK stable-channel packages are installed via sdkmanager, with actual emulator
and image source.properties archived. Tool/image revisions are not immutable:
a setup/image regression is a failed job with evidence, never a skipped PASS.
Existing setup-android is reused; no new emulator action. GitHub's documented
udev KVM permissions are applied only on the disposable hosted runner, with bounded settle/permission checks and retained diagnostics. AVD creation and launch share an explicit temporary ANDROID_AVD_HOME; registration, configuration and emulator discovery must agree before boot. HOME is not modified.

Each fresh AVD installs the universal debug APK, explicitly launches
`com.apporo.assistant/com.wangzan101.mika.ui.MainActivity`, waits for the actual
English `Meet Apporo Assistant` and `Get started` nodes owned by the app, checks
resumed activity and a stable PID for five seconds, captures PNG/XML, and checks
logcat plus API30+ exit reasons for Java/native crash or ANR. Then force-stop and
relaunch repeats the checks without clearing app data. No welcome button is
pressed, no account/permission granted, no helper pairing or tool calls.
App background initialization still runs normally. Screenshots are artifacts
for human review, not pixel-perfect layout assertions. Log absence covers only
this short startup window, not long-running stability.

Bounds: SDK480s, AVD60s, boot300s, install120s, each am-start45s / welcome90s,
individual adb calls5–30s; script overall1200s, job25min. SIGINT/SIGTERM and the
overall deadline terminate in-flight command groups; finally collects bounded
failure diagnostics, sends emulator kill, then TERM/KILL to its process group.
No daemon is intentionally left running beyond the hosted job. Hard runner
termination cannot guarantee final artifact upload; stage receipts are written
incrementally and setup failures get a NOT_RUN receipt when always() can run.

Artifacts (7 days): APK hash/native ABI list, source SHA, API/ABI/fingerprint,
SDK/install/emulator logs, cold-start and relaunch PNG/XML/activity/logcat/exit
info, status/elapsed time/cleanup receipt. `PASS_STARTUP_ONLY` is distinct from
setup failure, timeout or product crash. No CI run has been claimed by adding
this workflow; parent pushes and reviews first remote results.

Local lightweight validation (does not invoke adb/emulator/Gradle):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s apporo/tools -p 'test_startup_smoke.py'
```

Official references checked for this change:
- https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://developer.android.com/studio/run/emulator-acceleration (KVM, swiftshader)
- https://developer.android.com/studio/run/emulator-commandline (headless/cold boot)
- https://developer.android.com/tools/sdkmanager
- https://developer.android.com/reference/android/app/ApplicationExitInfo (crash4/native5/ANR6)
- https://github.com/actions/download-artifact (same-run artifact v8)

Image selection evidence:
- https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml (default x86_64 API30/32/35/36 available)
- https://android.googlesource.com/platform/prebuilts/android-emulator-build/system-images/+/refs/heads/main/generic/system-images/android-30/google_apis/x86_64/build.prop
- https://android.googlesource.com/platform/prebuilts/android-emulator-build/system-images/+/refs/heads/main/generic/system-images/android-35/google_apis/x86_64/build.prop
# AOSP System UI obstruction

If the disposable emulator shows the exact system-owned “System UI isn't responding” dialog, the runner records its XML, screenshot and log and may press **Wait once** for the entire run. It keeps the original 90-second deadline and requires the Apporo welcome page, stable process, resumed activity and no Apporo crash/ANR. App-specific ANRs, ambiguous controls and security dialogs never qualify. A recovery is listed in `receipt.json.environment_recoveries`; it is not a pristine-boot result. Repeated obstruction still fails.

