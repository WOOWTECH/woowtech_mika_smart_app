#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-provider-speech)"
trap 'rm -f "$binary"' EXIT
swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$root/Sources/AssistantModels/ProviderSpeech.swift" \
  "$root/Tests/ProviderSpeechStandalone/ProviderSpeechChecks.swift" -o "$binary"
"$binary"
