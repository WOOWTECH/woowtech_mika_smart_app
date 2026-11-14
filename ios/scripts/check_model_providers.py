#!/usr/bin/env python3
"""Exercise the provider document, the v1 import and Keychain order offline.

The actual ModelSettingsRepository runs with isolated defaults suites, a
temporary folder and an in-memory Keychain; nothing reaches a network.
"""
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="woow-model-providers-") as folder:
        build = Path(folder)
        common = ["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library"]
        sources = sorted((root / "Sources/AssistantModels").glob("*.swift"))
        subprocess.run([*common, "-strict-concurrency=complete", "-emit-module", "-emit-library",
                        "-module-name", "AssistantModels", "-emit-module-path", str(build / "AssistantModels.swiftmodule"),
                        *map(str, sources), "-o", str(build / "libAssistantModels.dylib")],
                       cwd=root, check=True, timeout=300)
        binary = build / "checks"
        subprocess.run([*common, "-I", str(build), "-L", str(build), "-lAssistantModels",
                        "-Xlinker", "-rpath", "-Xlinker", str(build),
                        str(root / "Sources/App/ModelSettings.swift"), str(root / "scripts/CheckModelProviders.swift"),
                        "-o", str(binary)], cwd=root, check=True, timeout=240)
        subprocess.run([str(binary)], cwd=root, check=True, timeout=60)


if __name__ == "__main__":
    main()
