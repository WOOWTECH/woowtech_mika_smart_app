#!/usr/bin/env python3
"""Exercise fake driver and verify its code is absent from a Release object."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
fixture = root / "Sources/App/VoiceUITestFixture.swift"
state = root / "Sources/App/VoiceInputStateMachine.swift"
controller = root / "Sources/App/ChatVoiceController.swift"
checks = root / "Tests/VoiceInputStandalone/VoiceUITestFixtureChecks.swift"
with tempfile.TemporaryDirectory(prefix="woow-voice-ui-fixture-") as directory:
    out = Path(directory)
    binary = out / "checks"
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-strict-concurrency=complete",
                    "-DDEBUG", "-DVOICE_UI_FIXTURE_STANDALONE", "-parse-as-library",
                    str(state), str(controller), str(fixture), str(checks), "-o", str(binary)], check=True, cwd=root, timeout=60)
    subprocess.run([str(binary)], check=True, cwd=root, timeout=30)
    release = out / "release.o"
    subprocess.run(["swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                    "-emit-object", str(fixture), "-o", str(release)], check=True, cwd=root, timeout=30)
    probe = release.read_bytes()
    for forbidden in (b"VoiceUITestFixture", b"-UITestVoiceFixture", b"fixture voice"):
        if forbidden in probe:
            raise SystemExit("Release unexpectedly contains voice fixture: " + repr(forbidden))
    print("PASS voice UI fixture excluded from Release object")
