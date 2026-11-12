#!/usr/bin/env python3
"""Fail closed unless every selected inbound XCTest started and passed once."""
import argparse
import json
from pathlib import Path
import re

EXPECTED = frozenset({
    "testAndroidToolSchemasAndOriginalAnswerSteerArguments",
    "testMaximumListResponsePreservesAllItemsAndBothRepresentations",
    "testParseErrorWithoutIDMatchesAndroidAndCanEncodeJSONRPCNull",
    "testExpiredConnectionFreesCapacityAndPendingReview",
    "testStaleDiscardAndApprovalPreserveReplacementReview",
})
PATTERN = re.compile(
    r"Test Case '-\[AssistantMCPTests\.MCPInboundCoreTests (test\w+)\]' "
    r"(started|passed|failed|skipped)(?:\.| \()"
)


def verify(summary, log):
    keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
    counts = {key: summary.get(key) for key in keys}
    if not all(type(value) is int and value >= 0 for value in counts.values()):
        return False
    if (summary.get("result") != "Passed" or counts["totalTestCount"] != counts["passedTests"]
            or counts["passedTests"] < len(EXPECTED)
            or any(counts[key] for key in ("failedTests", "skippedTests", "expectedFailures"))):
        return False
    seen = {}
    for name, outcome in PATTERN.findall(log):
        seen.setdefault(name, []).append(outcome)
    return set(seen) == EXPECTED and all(events == ["started", "passed"] for events in seen.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    try:
        passed = verify(json.loads(args.summary.read_text()), args.log.read_text(errors="replace"))
    except (OSError, ValueError, TypeError):
        passed = False
    if not passed:
        raise SystemExit("Inbound XCTest completion missing, repeated, skipped or failed")
    print("PASS: all five inbound XCTest methods started and passed once")


if __name__ == "__main__":
    main()
