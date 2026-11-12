#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$(mktemp -t woow-provider-pcm)"
trap 'rm -f "$binary"' EXIT
swiftc -swift-version 5 -parse-as-library -strict-concurrency=complete -warnings-as-errors \
  "$root/Sources/App/VoiceAudioLease.swift" "$root/Sources/App/VoiceInputStateMachine.swift" \
  "$root/Sources/App/ChatVoiceController.swift" \
  "$root/Sources/App/SharedVoiceAudioCoordinator.swift" "$root/Sources/App/MixedVoiceAudioCoordinator.swift" \
  "$root/Sources/App/ProviderPCMBuffer.swift" "$root/Sources/App/ProviderPCMVoiceDriver.swift" \
  "$root/Sources/App/CoordinatedProviderPCMSource.swift" "$root/Sources/App/AppleProviderPCMSource.swift" \
  "$root/Tests/ProviderPCMStandalone/ProviderPCMChecks.swift" -o "$binary"
"$binary"
