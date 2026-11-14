#!/usr/bin/env python3
"""Fresh-install Keychain reset decisions and real file probes; no Keychain or App container."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=root / "Sources/App/FreshInstallKeychainReset.swift",
                        help="check a changed copy instead (mutation tests)")
    source = parser.parse_args().source.resolve()
    with tempfile.TemporaryDirectory(prefix="woow-keychain-reset-") as folder:
        for config, flags in [("Debug", ["-DDEBUG"]), ("Release", [])]:
            binary, scratch = Path(folder) / config, Path(folder) / (config + "-scratch")
            scratch.mkdir()
            subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library", *flags,
                            str(source), str(root / "scripts/CheckFreshInstallKeychainReset.swift"), "-o", str(binary)],
                           cwd=root, check=True, timeout=240)
            subprocess.run([str(binary), str(scratch)], cwd=root, check=True, timeout=60)


if __name__ == "__main__":
    main()
