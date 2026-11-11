#!/usr/bin/env python3
"""Compile the production model client and exercise its requests without network."""
from pathlib import Path
import subprocess
import tempfile


def main():
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="woow-model-attachments-") as directory:
        executable = Path(directory) / "checks"
        sources = sorted((repo / "Sources/AssistantModels").glob("*.swift"))
        subprocess.run(["swiftc", "-warnings-as-errors", "-parse-as-library",
                        *map(str, sources), str(repo / "Tests/AssistantModelsTests/ModelProtocolFixture.swift"),
                        str(repo / "scripts/CheckModelAttachments.swift"),
                        "-o", str(executable)], check=True, timeout=120, cwd=repo)
        subprocess.run([str(executable)], check=True, timeout=60, cwd=repo)


if __name__ == "__main__":
    main()
