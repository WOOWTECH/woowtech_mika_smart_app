#!/usr/bin/env python3
"""Build the chat web task sources and run their logic checks on macOS.

Only AssistantModels and the address/command/runner files are compiled (no
WebKit, network, Keychain or user data); Debug and Release are both run.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BROWSER = ["BrowserPolicy", "ChatWebTaskPolicy", "ChatWebTaskTypes", "ChatWebTaskRunner"]


def main():
    with tempfile.TemporaryDirectory(prefix="woow-chat-web-core-") as folder:
        out = Path(folder)
        common = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(out), "-L", str(out)]
        subprocess.run(common + ["-emit-module", "-emit-library", "-module-name", "AssistantModels",
                                 "-emit-module-path", str(out / "AssistantModels.swiftmodule"),
                                 *map(str, sorted((ROOT / "Sources/AssistantModels").glob("*.swift"))),
                                 "-o", str(out / "libAssistantModels.dylib")], check=True, timeout=600)
        subprocess.run(common + ["-warnings-as-errors", "-emit-module", "-emit-library", "-module-name", "AssistantBrowser",
                                 "-emit-module-path", str(out / "AssistantBrowser.swiftmodule"), "-lAssistantModels",
                                 *[str(ROOT / "Sources/AssistantBrowser" / (name + ".swift")) for name in BROWSER],
                                 "-o", str(out / "libAssistantBrowser.dylib")], check=True, timeout=600)
        counts = {}
        for config, flags in [("Debug", ["-DDEBUG", "-Onone"]), ("Release", ["-O"])]:
            binary = out / ("checks-" + config)
            subprocess.run(common + flags + ["-warnings-as-errors", "-lAssistantModels", "-lAssistantBrowser",
                                             "-Xlinker", "-rpath", "-Xlinker", str(out),
                                             str(ROOT / "Tests/AssistantDomainTests/ChatWebTaskChecks.swift"),
                                             str(ROOT / "scripts/CheckChatWebTaskCore.swift"), "-o", str(binary)],
                           check=True, timeout=600)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=120)
            if result.returncode:
                print(result.stdout + result.stderr)
                raise SystemExit(config + " checks failed")
            counts[config] = json.loads(result.stdout)["assertions"]
        if counts["Debug"] != counts["Release"]:
            raise SystemExit("Debug and Release ran different checks")
        print("PASS chat web task core: " + json.dumps(counts))


if __name__ == "__main__":
    main()
