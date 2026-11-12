#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d -t woow-chat-voice)"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -parse-as-library -strict-concurrency=complete -warnings-as-errors \
  -emit-module -emit-library -module-name AssistantModels \
  "$root/Sources/AssistantModels/ProviderSpeech.swift" \
  -emit-module-path "$build/AssistantModels.swiftmodule" -o "$build/libAssistantModels.dylib"
build_and_run() {
  swiftc -swift-version 5 -parse-as-library -strict-concurrency=complete -warnings-as-errors "$@" \
    -I "$build" -L "$build" -lAssistantModels -Xlinker -rpath -Xlinker "$build" \
    "$root/Sources/App/VoiceInputStateMachine.swift" "$root/Sources/App/ChatVoiceController.swift" \
    "$root/Sources/App/VoiceChoiceStore.swift" "$root/Sources/App/VoicePreferences.swift" \
    "$root/Sources/App/ChatVoicePreferenceBinding.swift" \
    "$root/Tests/VoiceInputStandalone/ChatVoiceChecks.swift" -o "$build/checks"
  "$build/checks"
}
build_and_run -DDEBUG
build_and_run
