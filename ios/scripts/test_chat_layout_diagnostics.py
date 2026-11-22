#!/usr/bin/env python3
"""Focused Debug/optimized Release diagnostics limits, privacy and iOS syntax checks."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "Sources/App/ChatLayoutDiagnostics.swift"


class ChatLayoutDiagnosticsTests(unittest.TestCase):
    def run_swift(self, command, **kwargs):
        result = subprocess.run(command, capture_output=True, text=True, timeout=300, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_debug_and_release(self):
        with tempfile.TemporaryDirectory(prefix="woow-layout-check-") as directory:
            for config, flags in [("Debug", ["-DDEBUG", "-Onone"]), ("Release", ["-O"])]:
                with self.subTest(config=config):
                    binary = Path(directory) / config
                    self.run_swift(["swiftc", "-swift-version", "5", "-parse-as-library",
                                    "-warnings-as-errors", *flags, str(PROBE),
                                    str(ROOT / "scripts/CheckChatLayoutDiagnostics.swift"), "-o", str(binary)])
                    report = json.loads(self.run_swift([str(binary)]).stdout)
                    self.assertGreaterEqual(report["assertions"], 30)
                    print(json.dumps({"configuration": config, **report}), flush=True)

    def test_private_strings_rejected_by_api(self):
        with tempfile.TemporaryDirectory(prefix="woow-layout-privacy-") as directory:
            invalid = Path(directory) / "Rejected.swift"
            for statement in [
                'probe.record("PRIVATE_CONTENT")',
                'probe.record(.appendBegin, fields: ["PRIVATE_PATH": .flag(true)])',
                'probe.record(.appendBegin, fields: [.entries: .number("PRIVATE_UUID")])',
            ]:
                invalid.write_text("@MainActor func rejected(_ probe: ChatLayoutDiagnostics) {\n"
                                   + statement + "\n}\n")
                result = subprocess.run(["swiftc", "-swift-version", "5", "-typecheck", str(PROBE), str(invalid)],
                                        capture_output=True, text=True, timeout=300)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot convert value of type 'String'", result.stderr)

    def test_changed_ios_sources_parse(self):
        sources = ["ContentView", "ChatKeyboardDock", "ChatSession", "ChatLayoutDiagnostics"]
        for flags in [["-DDEBUG"], []]:
            self.run_swift(["swiftc", "-frontend", "-parse", "-target", "arm64-apple-ios17.0", *flags,
                            *[str(ROOT / ("Sources/App/" + name + ".swift")) for name in sources]])


if __name__ == "__main__":
    unittest.main()
