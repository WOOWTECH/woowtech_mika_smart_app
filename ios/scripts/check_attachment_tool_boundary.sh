#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."
boundary_build=$(mktemp -d "${TMPDIR:-/tmp}/woow-attachment-tools.XXXXXX")
trap 'rm -rf "$boundary_build"' EXIT
for boundary_module in AssistantModels AssistantMemory AssistantMCP; do
  boundary_deps=()
  if [[ "$boundary_module" != AssistantModels ]]; then boundary_deps=(-lAssistantModels); fi
  swiftc -swift-version 5 -warnings-as-errors -emit-module -emit-library -enable-testing \
    -module-name "$boundary_module" -I "$boundary_build" -L "$boundary_build" "${boundary_deps[@]}" \
    Sources/"$boundary_module"/*.swift -o "$boundary_build/lib$boundary_module.dylib" \
    -emit-module-path "$boundary_build/$boundary_module.swiftmodule"
done
swiftc -swift-version 5 -warnings-as-errors -parse-as-library -I "$boundary_build" -L "$boundary_build" \
  -lAssistantModels -lAssistantMemory -lAssistantMCP -Xlinker -rpath -Xlinker "$boundary_build" \
  scripts/CheckAttachmentToolBoundary.swift -o "$boundary_build/checks"
"$boundary_build/checks"
