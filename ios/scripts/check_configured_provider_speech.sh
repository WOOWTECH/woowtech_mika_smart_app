#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d -t woow-configured-speech)"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -enable-testing -parse-as-library -emit-module -emit-library \
  -module-name AssistantModels -emit-module-path "$build/AssistantModels.swiftmodule" \
  "$root"/Sources/AssistantModels/*.swift -o "$build/libAssistantModels.dylib"
swiftc -swift-version 5 -strict-concurrency=complete -warnings-as-errors -parse-as-library -I "$build" -L "$build" -lAssistantModels \
  -Xlinker -rpath -Xlinker "$build" "$root/Sources/App/ModelSettings.swift" \
  "$root/Sources/App/ConfiguredProviderSpeech.swift" \
  "$root/Sources/App/CandidateSpeechRouter.swift" \
  "$root/Sources/App/VoiceAudioLease.swift" "$root/Sources/App/VoiceInputStateMachine.swift" \
  "$root/Sources/App/ChatVoiceController.swift" "$root/Sources/App/VoiceChoiceStore.swift" \
  "$root/Sources/App/VoicePreferences.swift" "$root/Sources/App/ChatVoicePreferenceBinding.swift" \
  "$root/Sources/App/ProviderPCMBuffer.swift" "$root/Sources/App/ProviderPCMVoiceDriver.swift" \
  "$root/Tests/ProviderSpeechSettingsStandalone/ConfiguredProviderSpeechChecks.swift" -o "$build/checks"
"$build/checks"
