#!/usr/bin/env python3
"""MCP OAuth sign-in checks on loopback sockets and in-process fakes only; nothing reaches a real server.

Builds AssistantModels and AssistantMCP as modules, then compiles scripts/CheckMCPOAuth.swift with the App's
MCP settings and session sources, in Debug and Release with -warnings-as-errors, and runs the result. Also
checks that the fresh-install Keychain reset still removes the service that holds every server's sign-in.
--replace swaps one source for a changed copy (mutation tests).
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

MODULES = [("AssistantModels", []), ("AssistantMCP", ["AssistantModels"])]
APP = ["AppLanguage", "AppLocalizer", "AppText", "AppMCPText", "MCPSettings", "MCPSession"]
MCP_SERVICE = '"io.woowtech.assistant.mcp-endpoint.v1"'


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--replace", nargs=2, action="append", default=[], metavar=("SOURCE", "COPY"),
                        help="check a changed copy of one source instead (mutation tests)")
    parser.add_argument("--config", choices=["Debug", "Release"], action="append", help="default: both")
    arguments = parser.parse_args()
    replaced = {(root / source).resolve(): Path(copy).resolve() for source, copy in arguments.replace}

    def sources(paths):
        return [str(replaced.get(path.resolve(), path)) for path in paths]

    # Every server's sign-in lives in the one MCP service (account "<prefix>oauth"), which the
    # fresh-install reset removes whole after a reinstall.
    reset = Path(sources([root / "Sources/App/FreshInstallKeychainReset.swift"])[0]).read_text()
    settings = Path(sources([root / "Sources/App/MCPSettings.swift"])[0]).read_text()
    if MCP_SERVICE not in reset or "static let productionService = " + MCP_SERVICE not in settings:
        raise SystemExit("FAIL: the fresh-install reset no longer removes the MCP service that holds the sign-ins")
    configs = arguments.config or ["Debug", "Release"]
    with tempfile.TemporaryDirectory(prefix="woow-mcp-oauth-") as folder:
        for config in configs:
            out = Path(folder) / config
            out.mkdir()
            flags = ["-DDEBUG"] if config == "Debug" else []
            common = ["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library", *flags,
                      "-I", str(out), "-L", str(out)]
            for name, dependencies in MODULES:
                subprocess.run([*common, "-enable-testing", "-emit-module", "-emit-library", "-module-name", name,
                                "-emit-module-path", str(out / (name + ".swiftmodule")),
                                *sources(sorted((root / "Sources" / name).glob("*.swift"))),
                                *["-l" + dependency for dependency in dependencies], "-o", str(out / ("lib" + name + ".dylib"))],
                               cwd=root, check=True, timeout=900)
            binary = out / "checks"
            subprocess.run([*common, *["-l" + name for name, _ in MODULES], "-Xlinker", "-rpath", "-Xlinker", str(out),
                            *sources([root / "Sources/App" / (name + ".swift") for name in APP]),
                            str(root / "scripts/CheckMCPOAuth.swift"), "-o", str(binary)],
                           cwd=root, check=True, timeout=900)
            subprocess.run([str(binary)], cwd=root, check=True, timeout=300)


if __name__ == "__main__":
    main()
