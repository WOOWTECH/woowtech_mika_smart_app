#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-speech-consent)"
trap 'rm -f "$binary"' EXIT
swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  "$root/Sources/AssistantModels/ProviderSpeech.swift" \
  "$root/Sources/AssistantModels/SpeechUploadConsent.swift" \
  "$root/Tests/SpeechUploadConsentStandalone/SpeechUploadConsentChecks.swift" -o "$binary"
"$binary"
