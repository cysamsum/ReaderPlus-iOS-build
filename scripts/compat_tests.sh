#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
includes=()
while IFS= read -r folder; do includes+=("-I$folder"); done < <(find ThirdParty/SocketRocket -type d)
sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find ThirdParty/SocketRocket -name '*.m')
xcrun clang -c CompatApp/RPGEC.c -o build/compat-gec-test.o
xcrun clang -fobjc-arc -ICompatApp "${includes[@]}" scripts/compat_tests.m scripts/compat_pipeline_tests.m CompatApp/RPDocument.m CompatApp/RPSpeech.m CompatApp/RPAudioCache.m CompatApp/RPAudioPipeline.m build/compat-gec-test.o "${sources[@]}" \
  -framework Foundation -framework AVFoundation -framework CFNetwork -framework Security -framework CoreServices -lz -licucore -o build/compat-tests
set -o pipefail
build/compat-tests 2>&1 | tee build/compat-tests.log
build/compat-tests --live 2>&1 | tee build/compat-live.log
