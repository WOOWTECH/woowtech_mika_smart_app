#!/usr/bin/env python3
"""Compile real presenter, scope adapter and view; exercise only local fixtures."""
from pathlib import Path
import os
import subprocess
import tempfile


def main():
    repo = Path(__file__).resolve().parents[1]
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
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-typecheck",
                        str(repo / "Sources/App/ChatAttachmentPickerView.swift")], cwd=repo, check=True, timeout=120)
        binary = out / "checks"
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-L", str(out),
                        "-lAssistantModels", "-lAssistantAttachments", str(repo / "scripts/CheckChatAttachmentPresenter.swift"),
                        "-o", str(binary)], cwd=repo, check=True, timeout=120)
        subprocess.run([str(binary), str(fixture)], cwd=repo, check=True, timeout=60,
                       env={**os.environ, "DYLD_LIBRARY_PATH": str(out)})


if __name__ == "__main__":
    main()
