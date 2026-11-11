#!/usr/bin/env python3
"""Exercise actual transport and parser with URLProtocol; never use network."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="woow-model-usage-") as folder:
    binary = Path(folder) / "checks"
    sources = sorted((root / "Sources/AssistantModels").glob("*.swift"))
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                    *map(str, sources), str(root / "Tests/AssistantModelsTests/ModelProtocolFixture.swift"),
                    str(root / "scripts/CheckModelTokenUsage.swift"), "-o", str(binary)],
                   cwd=root, check=True, timeout=180)
    subprocess.run([str(binary)], cwd=root, check=True, timeout=60)
