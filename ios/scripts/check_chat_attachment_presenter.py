#!/usr/bin/env python3
"""Compile real presenter, scope adapter and view; exercise only local fixtures."""
from pathlib import Path
import os
import json
import plistlib
import re
import shutil
import subprocess
import tempfile


def main():
    repo = Path(__file__).resolve().parents[1]
    subprocess.run(["python3", str(repo / "scripts/generate_app_text.py")], cwd=repo, check=True, timeout=30)
    catalog = json.loads((repo / "Localization/AppText.json").read_text())
    declared = {entry["case"] for entry in catalog["entries"] if entry["case"].startswith("attachment")}
    view_paths = [repo / "Sources/App/ChatAttachmentPickerView.swift", repo / "Sources/App/AppAttachmentText.swift"]
    used = set(re.findall(r"\.(attachment[A-Z][A-Za-z0-9]*)", "\n".join(path.read_text() for path in view_paths)))
    used -= {"attachmentData", "attachmentDataDescription", "attachmentError", "attachmentKind"}
    if declared != used:
        raise SystemExit(f"Attachment localization case mismatch: missing={sorted(declared-used)}, undeclared={sorted(used-declared)}")
    with tempfile.TemporaryDirectory(prefix="woow-attachment-presenter-") as temporary:
        out = Path(temporary)
        fixture = out / "fixtures"
        fixture.mkdir()
        for name, deps in [("AssistantModels", []), ("AssistantAttachments", ["AssistantModels"])]:
            sources = sorted((repo / "Sources" / name).glob("*.swift"))
            subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-enable-testing", "-emit-library", "-emit-module",
                            "-module-name", name, "-I", str(out), "-L", str(out), *["-l" + dep for dep in deps],
                            *map(str, sources), "-emit-module-path", str(out / (name + ".swiftmodule")),
                            "-o", str(out / ("lib" + name + ".dylib"))], cwd=repo, check=True, timeout=120)
        app_sources = [repo / "Sources/App" / name for name in
                       ("AppLanguage.swift", "AppText.swift", "AppLocalizer.swift", "AppAttachmentText.swift")]
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-typecheck",
                        *map(str, app_sources), str(repo / "Sources/App/ChatAttachmentPickerView.swift")], cwd=repo, check=True, timeout=120)
        bundle = out / "Fixture.bundle"
        contents = bundle / "Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "io.woowtech.fixture", "CFBundlePackageType": "BNDL"}))
        for language in ("zh-Hant", "zh-Hans", "en"):
            shutil.copytree(repo / "Sources/App/Resources" / (language + ".lproj"), resources / (language + ".lproj"))
        localization = out / "localization"
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-L", str(out),
                        "-lAssistantModels", "-lAssistantAttachments", *map(str, app_sources),
                        str(repo / "scripts/CheckChatAttachmentLocalization.swift"), "-o", str(localization)],
                       cwd=repo, check=True, timeout=120)
        subprocess.run([str(localization), str(bundle)], cwd=repo, check=True, timeout=30,
                       env={**os.environ, "DYLD_LIBRARY_PATH": str(out)})
        binary = out / "checks"
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-L", str(out),
                        "-lAssistantModels", "-lAssistantAttachments", str(repo / "scripts/CheckChatAttachmentPresenter.swift"),
                        "-o", str(binary)], cwd=repo, check=True, timeout=120)
        subprocess.run([str(binary), str(fixture)], cwd=repo, check=True, timeout=60,
                       env={**os.environ, "DYLD_LIBRARY_PATH": str(out)})


if __name__ == "__main__":
    main()
