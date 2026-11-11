#!/usr/bin/env python3
"""Exercise the connection check offline with only isolated fixtures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="woow-model-connection-") as tmp:
    binary = Path(tmp) / "checks"
    sources = sorted((root / "Sources/AssistantModels").glob("*.swift"))
    subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library", *map(str, sources),
                    str(root / "Tests/AssistantModelsTests/ModelProtocolFixture.swift"),
                    str(root / "scripts/CheckModelConnection.swift"), "-o", str(binary)],
                   check=True, timeout=120, cwd=root)
    subprocess.run([str(binary)], check=True, timeout=30, cwd=root)
