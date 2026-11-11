#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
lan_policy_build=$(mktemp -d "${TMPDIR:-/tmp}/woow-lan-policy.XXXXXX")
trap 'rm -rf "$lan_policy_build"' EXIT
swiftc -swift-version 5 -warnings-as-errors -parse-as-library \
  Sources/AssistantBrowser/BrowserPolicy.swift Sources/AssistantBrowser/BrowserManualLANAccess.swift \
  scripts/CheckBrowserManualLAN.swift -o "$lan_policy_build/check"
"$lan_policy_build/check"
