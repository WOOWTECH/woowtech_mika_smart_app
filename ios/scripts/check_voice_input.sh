#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-voice-input)"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors "$root/Sources/App/VoiceInputStateMachine.swift" \
    "$root/Sources/App/AppleVoiceInputDriver.swift" \
    "$root/Sources/App/VoiceAudioLease.swift" \
    "$root/Tests/VoiceInputStandalone/VoiceInputChecks.swift" -o "$binary"
"$binary"
