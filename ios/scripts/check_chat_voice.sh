#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-chat-voice)"
trap 'rm -f "$binary"' EXIT
build_and_run() {
  swiftc -swift-version 5 -parse-as-library -strict-concurrency=complete -warnings-as-errors "$@" \
    "$root/Sources/App/VoiceInputStateMachine.swift" "$root/Sources/App/ChatVoiceController.swift" \
    "$root/Sources/App/VoiceChoiceStore.swift" "$root/Sources/App/VoicePreferences.swift" \
    "$root/Tests/VoiceInputStandalone/ChatVoiceChecks.swift" -o "$binary"
  "$binary"
}
build_and_run -DDEBUG
build_and_run
