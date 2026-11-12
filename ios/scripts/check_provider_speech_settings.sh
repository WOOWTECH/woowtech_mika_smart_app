#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="$(mktemp -d -t woow-speech-settings)"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors -parse-as-library -emit-module -emit-library \
  -module-name AssistantModels -emit-module-path "$build/AssistantModels.swiftmodule" \
  "$root"/Sources/AssistantModels/*.swift -o "$build/libAssistantModels.dylib"
cat > "$build/url-only.swift" <<'SWIFT'
import AssistantModels
import Foundation
let endpoint = SpeechProviderEndpoint(providerID: "fixture", kind: .openAICompatible,
    baseURL: URL(string: "https://site.invalid/v1")!)
SWIFT
if swiftc -swift-version 5 -typecheck -I "$build" "$build/url-only.swift" >"$build/url-only.log" 2>&1; then
  echo 'URL-only speech endpoint unexpectedly compiles' >&2
  exit 1
fi
case "$(cat "$build/url-only.log")" in
  *'initializer is inaccessible'*) ;;
  *) cat "$build/url-only.log" >&2; exit 1 ;;
esac
swiftc -swift-version 5 -warnings-as-errors -parse-as-library -I "$build" -L "$build" -lAssistantModels \
  -Xlinker -rpath -Xlinker "$build" "$root/Sources/App/ModelSettings.swift" \
  "$root/Tests/ProviderSpeechSettingsStandalone/ProviderSpeechSettingsChecks.swift" -o "$build/checks"
"$build/checks"
