#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-chat-voice)"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
  "$root/Sources/App/VoiceInputStateMachine.swift" "$root/Sources/App/ChatVoiceController.swift" \
  "$root/Tests/VoiceInputStandalone/ChatVoiceChecks.swift" -o "$binary"
"$binary"
