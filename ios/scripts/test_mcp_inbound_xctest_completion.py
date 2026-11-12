"""The native completion gate must reject absent, skipped and repeated cases."""
from pathlib import Path
import re
import unittest

import check_mcp_inbound_xctest_completion as gate

ROOT = Path(__file__).resolve().parents[1]


class InboundNativeCompletionTests(unittest.TestCase):
    def setUp(self):
        self.summary = {"result": "Passed", "totalTestCount": 9, "passedTests": 9,
                        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.lines = []
        for name in sorted(gate.EXPECTED):
            prefix = "Test Case '-[AssistantMCPTests.MCPInboundCoreTests " + name + "]' "
            self.lines.extend([prefix + "started.", prefix + "passed (0.1 seconds)."])

    def test_inventory_matches_actual_xctest_methods(self):
        source = (ROOT / "Tests/AssistantMCPTests/MCPInboundCoreTests.swift").read_text()
        self.assertEqual(set(re.findall(r'^    func (test\w+)\(', source, re.M)), gate.EXPECTED)

    def test_accepts_exact_completion(self):
        self.assertTrue(gate.verify(self.summary, "\n".join(self.lines)))

    def test_rejects_missing_started_failed_skipped_or_duplicate(self):
        mutations = [self.lines[1:], self.lines[:-1], self.lines + self.lines[:2],
                     [line.replace("passed (", "failed (") for line in self.lines],
                     [line.replace("passed (", "skipped (") for line in self.lines]]
        for lines in mutations:
            with self.subTest(lines=len(lines), last=lines[-1]):
                self.assertFalse(gate.verify(self.summary, "\n".join(lines)))

    def test_rejects_missing_bad_or_skipped_summary(self):
        for delta in ({"skippedTests": 1}, {"failedTests": 1}, {"expectedFailures": 1},
                      {"totalTestCount": 10}, {"passedTests": 4}, {"result": "Failed"},
                      {"passedTests": True}, {"totalTestCount": None}):
            with self.subTest(delta=delta):
                self.assertFalse(gate.verify({**self.summary, **delta}, "\n".join(self.lines)))
