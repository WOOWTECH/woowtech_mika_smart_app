#!/usr/bin/env python3
"""A server's page shows no secure text field while its sign-in page is open; source text only.

In the simulator run of 11/25 iOS offered to save a password over a server's sign-in page, which
still had a name field and a secure field. MCPServerDetail (Sources/App/MCPToolsView.swift)
therefore draws MCPSecretPlaceholder in place of the endpoint's and the client secret's SecureField
while `session.isSigningIn`. This reads that source (or --source, for mutation tests) and checks it.
It parses text; what iOS does with the page needs a device.
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# The secure fields that can be on the page while a sign-in runs. The token's shows only when the
# page signs in with a token, and a sign-in needs OAuth, so it never meets a sign-in page.
GUARDED = {".mcpEndpoint", ".mcpClientSecret"}
NEVER_WITH_A_SIGN_IN = {".mcpToken"}
SECURE_FIELD = re.compile(r"SecureField\(localizer\.text\((\.\w+)\)")
GUARD = re.compile(r"if session\.isSigningIn \{\s*MCPSecretPlaceholder\(localizer\.text\((\.\w+)\)\)\s*\} else \{\s*")


def struct_body(source, name):
    start = source.index("private struct " + name + ":")
    return source[start:source.index("\n}\n", start)]  # members are indented: the first `}` at column 0 ends it


def problems(source):
    if "private struct MCPSecretPlaceholder: View" not in source:
        return ["MCPSecretPlaceholder is gone"]
    body = struct_body(source, "MCPServerDetail")
    found = []
    for match in SECURE_FIELD.finditer(body):
        title = match.group(1)
        if title in NEVER_WITH_A_SIGN_IN:
            continue
        if title not in GUARDED:
            found.append(f"a secure field titled {title} is new on the server page: can a sign-in page open beside it?")
            continue
        before = body[:match.start()]
        guard = GUARD.fullmatch(before[before.rfind("if session.isSigningIn {"):]) if "if session.isSigningIn {" in before else None
        if guard is None or guard.group(1) != title:
            found.append(f"the secure field titled {title} is on screen while a sign-in page is open")
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Sources/App/MCPToolsView.swift",
                        help="check a changed copy instead (mutation tests)")
    found = problems(parser.parse_args().source.read_text())
    if found:
        raise SystemExit("FAIL: " + "; ".join(found))
    print("PASS MCP server page: no secure text field is on screen while a sign-in page is open (source text only)")


if __name__ == "__main__":
    main()
