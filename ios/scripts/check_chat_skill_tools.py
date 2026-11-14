#!/usr/bin/env python3
"""Exercise the Play build's chat skill tools offline, in Debug and Release.

Builds AssistantModels, AssistantSkills and AssistantMemory as they ship and runs
scripts/CheckChatSkillTools.swift against the bundled skill archive with
scripted model replies. No network, model endpoint, Keychain or user data.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

MODULES = [
    ("AssistantModels", []),
    ("AssistantSkills", ["AssistantModels"]),
    ("AssistantMemory", ["AssistantModels"]),
]


def build_and_run(root: Path, build: Path, release: bool) -> str:
    optimize = ["-O"] if release else ["-Onone", "-DDEBUG"]
    common = ["swiftc", "-swift-version", "5", "-parse-as-library", *optimize]
    for name, dependencies in MODULES:
        sources = sorted((root / "Sources" / name).glob("*.swift"))
        links = [flag for dependency in dependencies for flag in ("-l" + dependency,)]
        subprocess.run([*common, "-emit-module", "-emit-library", "-module-name", name,
                        "-emit-module-path", str(build / f"{name}.swiftmodule"),
                        "-I", str(build), "-L", str(build), *links,
                        "-Xlinker", "-install_name", "-Xlinker", f"@rpath/lib{name}.dylib",
                        *map(str, sources), "-o", str(build / f"lib{name}.dylib")],
                       cwd=root, check=True, timeout=400)
    binary = build / "checks"
    subprocess.run([*common, "-warnings-as-errors", "-I", str(build), "-L", str(build),
                    *[f"-l{name}" for name, _ in MODULES],
                    "-Xlinker", "-rpath", "-Xlinker", str(build),
                    str(root / "scripts/CheckChatSkillTools.swift"), "-o", str(binary)],
                   cwd=root, check=True, timeout=240)
    result = subprocess.run([str(binary), str(root / "Sources/AssistantSkills/Resources/MikaBundledSkills.json")],
                            cwd=root, capture_output=True, text=True, timeout=120)
    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0 or not output.startswith("PASS"):
        raise SystemExit(f"{'Release' if release else 'Debug'}: {output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["Debug", "Release", "both"], default="both")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    configurations = ["Debug", "Release"] if args.configuration == "both" else [args.configuration]
    for configuration in configurations:
        with tempfile.TemporaryDirectory(prefix="woow-chat-skill-tools-") as folder:
            print(f"{configuration}: {build_and_run(root, Path(folder), configuration == 'Release')}")


if __name__ == "__main__":
    main()
