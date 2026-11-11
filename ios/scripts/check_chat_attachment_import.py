#!/usr/bin/env python3
"""Compile actual attachment core and exercise it with synthetic local files."""
from pathlib import Path
import os
import subprocess
import tempfile


def main():
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="woow-attachment-import-") as temporary:
        out = Path(temporary)
        fixture = out / "fixtures"
        fixture.mkdir()
        for name, dependencies in [("AssistantModels", []), ("AssistantAttachments", ["AssistantModels"])]:
            sources = sorted((repo / "Sources" / name).glob("*.swift"))
            command = ["swiftc", "-warnings-as-errors", "-parse-as-library", "-emit-library", "-emit-module",
                       "-module-name", name, "-I", str(out), "-L", str(out),
                       *["-l" + dep for dep in dependencies], *map(str, sources),
                       "-emit-module-path", str(out / (name + ".swiftmodule")), "-o", str(out / ("lib" + name + ".dylib"))]
            subprocess.run(command, cwd=repo, check=True, timeout=120)
        binary = out / "checks"
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", "-I", str(out), "-L", str(out),
                        "-lAssistantModels", "-lAssistantAttachments", str(repo / "scripts/CheckChatAttachmentImport.swift"),
                        "-o", str(binary)], cwd=repo, check=True, timeout=120)
        subprocess.run([str(binary), str(fixture)], cwd=repo, check=True, timeout=60,
                       env={**os.environ, "DYLD_LIBRARY_PATH": str(out)})


if __name__ == "__main__":
    main()
