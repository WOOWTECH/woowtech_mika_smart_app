#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
names_build=$(mktemp -d "${TMPDIR:-/tmp}/woow-download-names.XXXXXX")
trap 'rm -rf "$names_build"' EXIT
swiftc -emit-module -emit-library -enable-testing -module-name AssistantModels \
  Sources/AssistantModels/*.swift -o "$names_build/libAssistantModels.dylib" \
  -emit-module-path "$names_build/AssistantModels.swiftmodule"
swiftc -emit-module -emit-library -enable-testing -module-name AssistantBrowser \
  -I "$names_build" -L "$names_build" -lAssistantModels \
  Sources/AssistantBrowser/*.swift -o "$names_build/libAssistantBrowser.dylib" \
  -emit-module-path "$names_build/AssistantBrowser.swiftmodule"
swiftc -I "$names_build" -L "$names_build" -lAssistantModels -lAssistantBrowser \
  -Xlinker -rpath -Xlinker "$names_build" \
  Tests/BrowserDownloadNamesStandalone/BrowserDownloadNamesChecks.swift -o "$names_build/download-name-checks"
"$names_build/download-name-checks"
