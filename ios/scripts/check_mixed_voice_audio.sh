#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-mixed-audio)"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    "$root/Sources/App/VoiceAudioLease.swift" "$root/Sources/App/SharedVoiceAudioCoordinator.swift" \
    "$root/Sources/App/VoiceInputStateMachine.swift" "$root/Sources/App/MixedVoiceAudioCoordinator.swift" "$root/Sources/App/AppleMixedVoiceAudioSession.swift" \
    "$root/Tests/MixedVoiceAudioStandalone/MixedVoiceAudioChecks.swift" -o "$binary"
"$binary"
