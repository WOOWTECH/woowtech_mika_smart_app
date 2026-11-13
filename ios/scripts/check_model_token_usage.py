#!/usr/bin/env python3
"""Exercise token usage through the actual transport and parser; never use network."""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="woow-model-usage-") as folder:
        binary = Path(folder) / "checks"
        sources = sorted((root / "Sources/AssistantModels").glob("*.swift"))
        subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                        *map(str, sources), str(root / "Tests/AssistantModelsTests/ModelProtocolFixture.swift"),
                        str(root / "scripts/CheckModelTokenUsage.swift"), "-o", str(binary)],
                       cwd=root, check=True, timeout=240)
        subprocess.run([str(binary)], cwd=root, check=True, timeout=60)


if __name__ == "__main__":
    main()
