#!/usr/bin/env python3
"""Compile and exercise the opt-in delayed fixture without network or user data."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="woow-connection-delayed-") as tmp:
    out = Path(tmp)
    modules = sorted((root / "Sources/AssistantModels").glob("*.swift"))
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-DDEBUG",
                    "-parse-as-library", "-emit-module", "-emit-library", "-module-name", "AssistantModels",
                    "-emit-module-path", str(out / "AssistantModels.swiftmodule"), *map(str, modules),
                    "-o", str(out / "libAssistantModels.dylib")], check=True, timeout=120, cwd=root)
    binary = out / "checks"
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-DDEBUG",
                    "-DMODEL_CONNECTION_FIXTURE_STANDALONE", "-parse-as-library", "-I", str(out),
                    "-L", str(out), "-lAssistantModels", "-Xlinker", "-rpath", "-Xlinker", str(out),
                    str(root / "Sources/App/ModelConnectionUITestFixture.swift"),
                    str(root / "scripts/CheckModelConnectionDelayedFixture.swift"), "-o", str(binary)],
                   check=True, timeout=120, cwd=root)
    subprocess.run([str(binary)], check=True, timeout=30, cwd=root)

    # A Release module must not expose the DEBUG completion observer, and the
    # fixture's opt-in flag/client must not survive compilation without DEBUG.
    release = out / "release"
    release.mkdir()
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                    "-emit-module", "-module-name", "AssistantModels", "-emit-module-path",
                    str(release / "AssistantModels.swiftmodule"), *map(str, modules)],
                   check=True, timeout=120, cwd=root)
    probe = release / "probe.swift"
    probe.write_text("import AssistantModels\n@MainActor func check(_ value: ModelConnectionCheck) { _ = value.onFixtureAttemptSettled }\n")
    result = subprocess.run(["swiftc", "-swift-version", "5", "-typecheck", "-I", str(release), str(probe)],
                            capture_output=True, text=True, timeout=30, cwd=root)
    if result.returncode == 0 or "onFixtureAttemptSettled" not in result.stderr:
        raise SystemExit("Release unexpectedly exposes the fixture observer")
    obj = release / "fixture.o"
    subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", "-emit-object",
                    str(root / "Sources/App/ModelConnectionUITestFixture.swift"), "-o", str(obj)],
                   check=True, timeout=30, cwd=root)
    if b"-UITestModelConnectionDelay" in obj.read_bytes() or b"DelayedModelConnectionUITestClient" in obj.read_bytes():
        raise SystemExit("Release unexpectedly contains the delayed fixture")
    print("PASS release fixture exclusion: observer, flag and client absent")
