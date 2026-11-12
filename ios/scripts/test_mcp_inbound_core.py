"""Build and execute the real bounded inbound parser/review core without network."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MCPInboundCoreTests(unittest.TestCase):
    def test_response_and_review_regressions(self):
        with tempfile.TemporaryDirectory(prefix="woow-inbound-response-review-") as tmp:
            binary = pathlib.Path(tmp) / "checks"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundResponses.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/ResponseReviewRegressionChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=90)
            self.assertIn("PASS response review regressions: 30 checks; synthetic only", result.stdout)

    def test_conversation_and_response(self):
        with tempfile.TemporaryDirectory(prefix="woow-inbound-conversation-") as tmp:
            binary = pathlib.Path(tmp) / "checks"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundResponses.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/ConversationResponseChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn("PASS conversation and response: 58 checks; synthetic only", result.stdout)

    def test_android_compatibility_and_independent_review_regressions(self):
        for fixture, expected in [
            ("AndroidCompatibilityChecks.swift", "PASS Android compatibility: 21 checks; synthetic only"),
            ("ReviewFixChecks.swift", "INBOUND_INDEPENDENT_PASS checks=50 synthetic_only=1"),
        ]:
            with self.subTest(fixture=fixture), tempfile.TemporaryDirectory(prefix="woow-mcp-inbound-regression-") as tmp:
                binary = pathlib.Path(tmp) / "checks"
                subprocess.run([
                    "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                    str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                    str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                    str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                    str(ROOT / "Tests/MCPInboundStandalone" / fixture), "-o", str(binary),
                ], check=True, timeout=120)
                result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=20)
                self.assertIn(expected, result.stdout)

    def test_wait_answer_and_steer(self):
        with tempfile.TemporaryDirectory(prefix="woow-mcp-inbound-interactions-") as tmp:
            binary = pathlib.Path(tmp) / "interactions-check"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/InteractionChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn("PASS interactions: 65 checks; synthetic only", result.stdout)

    def test_access_and_inert_task_state(self):
        with tempfile.TemporaryDirectory(prefix="woow-mcp-inbound-access-") as tmp:
            binary = pathlib.Path(tmp) / "access-check"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/AccessTaskChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=15)
            self.assertIn("PASS access/tasks: 107 checks; synthetic only", result.stdout)

    def test_format_and_review_state(self):
        with tempfile.TemporaryDirectory(prefix="woow-mcp-inbound-") as tmp:
            binary = pathlib.Path(tmp) / "inbound-check"
            subprocess.run([
                "swiftc", "-swift-version", "5", "-warnings-as-errors", "-parse-as-library",
                str(ROOT / "Sources/AssistantMCP/MCPTypes.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundCore.swift"),
                str(ROOT / "Sources/AssistantMCP/MCPInboundAccessTasks.swift"),
                str(ROOT / "Tests/MCPInboundStandalone/InboundChecks.swift"), "-o", str(binary),
            ], check=True, timeout=120)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=15)
            self.assertIn("PASS inbound: 49 checks; no network, storage, UI, or model", result.stdout)


if __name__ == "__main__":
    unittest.main()
