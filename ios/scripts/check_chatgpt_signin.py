#!/usr/bin/env python3
"""ChatGPT sign-in prototype checks on loopback sockets only; nothing reaches OpenAI."""
import argparse
from pathlib import Path
import subprocess
import tempfile

SOURCES = ["Sources/AssistantModels/ChatGPTSignIn.swift", "Sources/AssistantModels/LoopbackCallbackServer.swift",
           "Sources/AssistantModels/ChatGPTResponses.swift"]


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace", nargs=2, action="append", default=[], metavar=("SOURCE", "COPY"),
                        help="check a changed copy of one source instead (mutation tests)")
    parser.add_argument("--config", choices=["Debug", "Release"], action="append", help="default: both")
    arguments = parser.parse_args()
    replaced = {(root / source).resolve(): Path(copy).resolve() for source, copy in arguments.replace}
    sources = [str(replaced.get((root / source).resolve(), root / source)) for source in SOURCES]
    configs = arguments.config or ["Debug", "Release"]
    with tempfile.TemporaryDirectory(prefix="woow-chatgpt-signin-") as folder:
        for config in configs:
            binary = Path(folder) / config
            flags = ["-DDEBUG"] if config == "Debug" else []
            subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library", *flags, *sources,
                            str(root / "scripts/CheckChatGPTSignIn.swift"), "-o", str(binary)],
                           cwd=root, check=True, timeout=600)
            subprocess.run([str(binary)], cwd=root, check=True, timeout=300)


if __name__ == "__main__":
    main()
