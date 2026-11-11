#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-audio-coordinator)"
trap 'rm -f "$binary"' EXIT
swiftc -parse-as-library -strict-concurrency=complete -warnings-as-errors \
    "$root/Sources/App/VoiceAudioLease.swift" "$root/Sources/App/SharedVoiceAudioCoordinator.swift" \
    "$root/Sources/App/AppleVoiceAudioSessionAccess.swift" \
    "$root/Sources/App/VoiceAudioAdmissionFence.swift" \
    "$root/Sources/App/VoiceAudioRuntimeCandidate.swift" \
    "$root/Tests/VoiceAudioCoordinatorStandalone/VoiceAudioCoordinatorChecks.swift" -o "$binary"
"$binary"
