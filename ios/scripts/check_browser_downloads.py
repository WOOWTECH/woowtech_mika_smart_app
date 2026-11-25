#!/usr/bin/env python3
"""Check the rules behind browser downloads and created files, in Debug and Release.

Builds AssistantModels, AssistantSkills and AssistantBrowser as they ship and
runs scripts/CheckBrowserDownloads.swift with the App's ChatCreatedFiles.swift:
the question's answer and its two minutes, the 200 MB and 500 MB limits, file
names, Content-Disposition, cleanup after a day, what a restart lists again,
and the created-file store's limit. Real files in a temporary folder; no page,
network, Keychain or user data. The same sources also typecheck for iOS 17.

Run it under the shared compiler lock:
/usr/bin/lockf -k /tmp/woow-swiftc.lock python3 scripts/check_browser_downloads.py
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODULES = [("AssistantModels", []), ("AssistantSkills", ["AssistantModels"]),
           ("AssistantBrowser", ["AssistantModels", "AssistantSkills"])]
APP = [str(ROOT / "Sources/App/ChatCreatedFiles.swift")]


def run(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=900)
    if result.returncode:
        raise SystemExit(" ".join(map(str, command[:3])) + " failed:\n" + result.stdout + result.stderr)
    return result.stdout


def build(out, extra):
    for name, dependencies in MODULES:
        sources = [str(p) for p in sorted((ROOT / "Sources" / name).glob("*.swift"))]
        run(["swiftc", "-swift-version", "5", "-parse-as-library", *extra, "-I", str(out), "-L", str(out),
             *[f"-l{d}" for d in dependencies], "-emit-module", "-emit-library", "-module-name", name,
             "-emit-module-path", str(out / f"{name}.swiftmodule"),
             "-Xlinker", "-install_name", "-Xlinker", f"@rpath/lib{name}.dylib",
             *sources, "-o", str(out / f"lib{name}.dylib")])


def main():
    counts = {}
    with tempfile.TemporaryDirectory(prefix="woow-browser-downloads-") as scratch:
        scratch = Path(scratch)
        for config, flags in [("Debug", ["-Onone", "-DDEBUG"]), ("Release", ["-O"])]:
            out = scratch / config
            out.mkdir()
            build(out, flags)
            run(["swiftc", "-swift-version", "5", "-parse-as-library", "-warnings-as-errors", *flags,
                 "-I", str(out), "-L", str(out), *[f"-l{name}" for name, _ in MODULES],
                 "-Xlinker", "-rpath", "-Xlinker", str(out), *APP,
                 str(ROOT / "scripts/CheckBrowserDownloads.swift"), "-o", str(out / "check")])
            counts[config] = json.loads(run([str(out / "check")]))["assertions"]
            print(f"{config}: {counts[config]} assertions", flush=True)
        if counts["Debug"] != counts["Release"]:
            raise SystemExit("Debug and Release ran different checks")
        sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"]).strip()
        ios = scratch / "ios"
        ios.mkdir()
        device = ["-sdk", sdk, "-target", "arm64-apple-ios17.0"]
        for name, _ in MODULES:
            sources = [str(p) for p in sorted((ROOT / "Sources" / name).glob("*.swift"))]
            run(["swiftc", "-swift-version", "5", "-parse-as-library", *device, "-I", str(ios), "-emit-module",
                 "-module-name", name, "-emit-module-path", str(ios / f"{name}.swiftmodule"), *sources])
        run(["swiftc", "-typecheck", "-swift-version", "5", "-parse-as-library", "-warnings-as-errors", *device,
             "-I", str(ios), *APP])
    print(f"PASS browser downloads: {counts['Release']} assertions in Debug and Release; iOS 17 typecheck")


if __name__ == "__main__":
    main()
