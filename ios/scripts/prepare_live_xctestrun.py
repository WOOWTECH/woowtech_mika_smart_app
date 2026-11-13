"""Inject live credentials into a private, ephemeral XCTest runner configuration.

Never upload the resulting .xctestrun, live xcresult, screenshots or crash logs.
No credential or endpoint is printed. --clear removes the injected variables.
"""
import argparse
import os
import pathlib
import plistlib
import sys
from urllib.parse import urlsplit

MAPPING = {
    "WOOW_MODEL_TEST_BASE_URL": "WOOW_LIVE_BASE_URL",
    "WOOW_MODEL_TEST_MODEL": "WOOW_LIVE_MODEL",
    "WOOW_MODEL_TEST_API_KEY": "WOOW_LIVE_API_KEY",
}
MCP_MAPPING = {"WOOW_HA_MCP_TEST_URL": "WOOW_LIVE_MCP_URL"}


def validate_mcp_secret(raw):
    """Fail closed on JSON string escapes before writing a private runner file."""
    try:
        if (not isinstance(raw, str) or not raw or len(raw.encode("utf-8")) > 16_384
                or any(c.isspace() or ord(c) < 32 or c in ('\\', '"') for c in raw)
                or '#' in raw):
            raise ValueError
        parsed = urlsplit(raw)
        if (parsed.scheme.lower() != "https" or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or parsed.port is not None and not 1 <= parsed.port <= 65535):
            raise ValueError
    except (ValueError, TypeError):
        raise ValueError("Invalid private MCP endpoint") from None
    return raw


def configure(payload, environment, clear=False, service="model"):
    if service not in ("model", "mcp"):
        raise ValueError("Unsupported live service")
    mapping = MAPPING if service == "model" else MCP_MAPPING
    targets = []
    if "TestConfigurations" in payload:
        for configuration in payload["TestConfigurations"]:
            for target in configuration.get("TestTargets", []):
                if target.get("BlueprintName") == "WoowAssistantUITests":
                    targets.append(target)
    else:
        target = payload.get("WoowAssistantUITests")
        if isinstance(target, dict):
            targets.append(target)
    if len(targets) != 1:
        raise ValueError("Expected exactly one WoowAssistantUITests runner")
    if not clear and any(not environment.get(source) for source in mapping):
        raise ValueError("Missing live test configuration")
    if not clear and service == "mcp":
        validate_mcp_secret(environment["WOOW_HA_MCP_TEST_URL"])
    variables = targets[0].setdefault("EnvironmentVariables", {})
    for source, destination in mapping.items():
        if clear:
            variables.pop(destination, None)
        else:
            variables[destination] = environment[source]
    return payload


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=pathlib.Path)
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--service", choices=("model", "mcp"), default="model")
    args = parser.parse_args()
    try:
        if args.path.is_symlink() or not args.path.is_file():
            raise ValueError("Expected a generated regular xctestrun file")
        with args.path.open("rb") as source:
            payload = plistlib.load(source)
        updated = configure(payload, os.environ, args.clear, args.service)
        os.chmod(args.path, 0o600)
        with args.path.open("wb") as output:
            plistlib.dump(updated, output)
        print("Live runner configuration cleared" if args.clear else "Live runner configured privately")
    except Exception:
        print("Could not prepare the private live test runner", file=sys.stderr)
        sys.exit(1)
