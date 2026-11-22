#!/usr/bin/env python3
"""Account sign-in checks (ChatGPT and xAI / Grok) on loopback sockets only; nothing reaches OpenAI or xAI.

Compiles the AssistantModels sources with scripts/CheckChatGPTSignIn.swift, in Debug and Release,
and runs the result. --replace swaps one source for a changed copy (mutation tests).
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace", nargs=2, action="append", default=[], metavar=("SOURCE", "COPY"),
                        help="check a changed copy of one source instead (mutation tests)")
    parser.add_argument("--config", choices=["Debug", "Release"], action="append", help="default: both")
    arguments = parser.parse_args()
    replaced = {(root / source).resolve(): Path(copy).resolve() for source, copy in arguments.replace}
    sources = [str(replaced.get(path.resolve(), path)) for path in sorted((root / "Sources/AssistantModels").glob("*.swift"))]
    configs = arguments.config or ["Debug", "Release"]
    with tempfile.TemporaryDirectory(prefix="woow-account-signin-") as folder:
        for config in configs:
            binary = Path(folder) / config
            flags = ["-DDEBUG"] if config == "Debug" else []
            subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library", *flags, *sources,
                            str(root / "scripts/CheckChatGPTSignIn.swift"), "-o", str(binary)],
                           cwd=root, check=True, timeout=900)
            subprocess.run([str(binary)], cwd=root, check=True, timeout=300)


if __name__ == "__main__":
    main()
