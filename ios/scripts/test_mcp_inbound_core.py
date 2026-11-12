"""Build and execute the real bounded inbound parser/review core without network."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MCPInboundCoreTests(unittest.TestCase):
    def test_format_and_review_state(self):
        with tempfile.TemporaryDirectory(prefix="woow-mcp-inbound-") as tmp:
            binary = pathlib.Path(tmp) / "inbound-check"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/InboundChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=15)
            self.assertIn("PASS inbound: 47 checks; no network, storage, UI, or model", result.stdout)


if __name__ == "__main__":
    unittest.main()
