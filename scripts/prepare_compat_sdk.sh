#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
if [ ! -d build/compat-sdks/.git ]; then
  git clone --filter=blob:none --sparse --no-checkout https://github.com/theos/sdks.git build/compat-sdks
fi
git -C build/compat-sdks sparse-checkout set iPhoneOS9.3.sdk iPhoneOS12.4.sdk
git -C build/compat-sdks checkout 0222fd5413cf4b9af096f37b4621afa2688572f7
