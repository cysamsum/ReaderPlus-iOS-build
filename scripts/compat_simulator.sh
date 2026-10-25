#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available --json > build/compat-devices.json
device=$(python3 -c 'import json; d=json.load(open("build/compat-devices.json")); p=[x for r,a in d["devices"].items() for x in a if "iOS-26-1" in r and "iPhone" in x["name"]]; assert p,"No iOS 26.1 simulator"; print(p[0]["udid"])')
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" build/compat-simulator/ReaderPlus.app
xcrun simctl launch "$device" org.readerplus.ios
sleep 4
xcrun simctl io "$device" screenshot build/compat-bookshelf.png
xcrun simctl terminate "$device" org.readerplus.ios
xcrun simctl launch "$device" org.readerplus.ios --smoke-reader
sleep 5
xcrun simctl io "$device" screenshot build/compat-reader.png
xcrun simctl spawn "$device" log show --last 2m --style compact --predicate 'process == "ReaderPlus"' > build/compat-console.log
xcrun simctl terminate "$device" org.readerplus.ios
xcrun simctl launch "$device" org.readerplus.ios --smoke-audio
container=$(xcrun simctl get_app_container "$device" org.readerplus.ios data)
for attempt in $(seq 1 120); do
  if [ -f "$container/Documents/audio-regression.json" ]; then break; fi
  sleep 1
done
cp "$container/Documents/audio-regression.json" build/compat-audio-regression.json
python3 -c 'import json; d=json.load(open("build/compat-audio-regression.json")); print(d); assert d["passed"],d'
