#!/usr/bin/env bash
# Synthetic fixtures only: no microphone, service, or user credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rm -f build/check_provider_speech.log build/check_provider_speech_settings.log \
  build/check_configured_provider_speech.log build/check_provider_pcm.log \
  build/provider-speech-source-commit.log
git rev-parse HEAD > build/provider-speech-source-commit.log
for check in check_provider_speech check_provider_speech_settings check_configured_provider_speech check_provider_pcm; do
  bash "scripts/${check}.sh" 2>&1 | tee "build/${check}.log"
done
