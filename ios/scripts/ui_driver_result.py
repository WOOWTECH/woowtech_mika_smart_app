"""Require the native UI driver's successful exit and a complete step log."""
import re


def failure_reason(exit_code, steps, log):
    if exit_code:
        return f"native UI test exited {exit_code}"
    if not steps:
        return "no UI steps were requested"
    if re.search(r"^FAILED:", log, re.MULTILINE):
        return "UI driver recorded a failed step"
    actual = re.findall(r"^step (\d+): (.*)$", log, re.MULTILINE)
    expected = [(str(index), step) for index, step in enumerate(steps, 1)]
    if actual != expected:
        return "UI driver did not execute the requested steps exactly once in order"
    if f"COMPLETED: {len(steps)} steps" not in log.splitlines():
        return "UI driver did not record completion"
    return None
