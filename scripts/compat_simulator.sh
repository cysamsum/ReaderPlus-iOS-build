#!/bin/bash
set -euxo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available --json > build/compat-devices.json
device=$(python3 -c 'import json; d=json.load(open("build/compat-devices.json")); p=[x for r,a in d["devices"].items() for x in a if "iOS-26-1" in r and "iPhone" in x["name"]]; assert p,"No iOS 26.1 simulator"; p.sort(key=lambda x: x["name"]!="iPhone 17 Pro"); print(p[0]["udid"])')
xcrun simctl boot "$device" || true
python3 -c 'import subprocess,sys; subprocess.run(["xcrun","simctl","bootstatus",sys.argv[1],"-b"],check=True,timeout=240)' "$device"
xcrun simctl install "$device" build/compat-simulator/ReaderPlus.app
xcrun simctl launch "$device" org.readerplus.ios
sleep 4
xcrun simctl io "$device" screenshot build/compat-bookshelf.png
xcrun simctl terminate "$device" org.readerplus.ios
xcrun simctl launch "$device" org.readerplus.ios --smoke-reader
sleep 5
xcrun simctl io "$device" screenshot build/compat-reader.png
xcrun simctl terminate "$device" org.readerplus.ios
container=$(xcrun simctl get_app_container "$device" org.readerplus.ios data)
xcrun simctl launch "$device" org.readerplus.ios --smoke-import
sleep 6
cp "$container/Documents/import-regression.json" build/compat-import-native.json
xcrun simctl io "$device" screenshot build/compat-import-native.png
python3 -c 'import json; d=json.load(open("build/compat-import-native.json")); print(d); assert d["passed"] and d["systemPickerVisible"],d'
xcrun simctl terminate "$device" org.readerplus.ios
python3 -c 'from pathlib import Path; import shutil,sys; shutil.copyfile(next(Path("samples").glob("*.epub")),Path(sys.argv[1])/"Documents"/"PickerTest.epub")' "$container"
xcrun simctl launch "$device" org.readerplus.ios --smoke-import --smoke-local-picker
sleep 6
cp "$container/Documents/import-regression.json" build/compat-import-local.json
xcrun simctl io "$device" screenshot build/compat-import-local.png
python3 -c 'import json; d=json.load(open("build/compat-import-local.json")); print(d); assert d["passed"] and d["localPickerVisible"],d'
xcrun simctl terminate "$device" org.readerplus.ios
xcrun simctl launch "$device" org.readerplus.ios --smoke-picker-import
for attempt in $(seq 1 30); do
  if [ -f "$container/Documents/picker-import-regression.json" ]; then break; fi
  sleep 1
done
cp "$container/Documents/picker-import-regression.json" build/compat-picker-selected.json
python3 -c 'import json; d=json.load(open("build/compat-picker-selected.json")); print(d); assert d["passed"] and not d["detachedPicker"] and d["format"]=="epub",d'
xcrun simctl io "$device" screenshot build/compat-picker-selected.png
xcrun simctl terminate "$device" org.readerplus.ios
rm "$container/Documents/picker-import-regression.json"
xcrun simctl launch "$device" org.readerplus.ios --smoke-picker-import --smoke-picker-detached
for attempt in $(seq 1 30); do
  if [ -f "$container/Documents/picker-import-regression.json" ]; then break; fi
  sleep 1
done
cp "$container/Documents/picker-import-regression.json" build/compat-picker-detached.json
python3 -c 'import json; d=json.load(open("build/compat-picker-detached.json")); print(d); assert d["passed"] and d["detachedPicker"] and d["format"]=="epub",d'
xcrun simctl io "$device" screenshot build/compat-picker-detached.png
xcrun simctl terminate "$device" org.readerplus.ios
xcrun simctl launch "$device" org.readerplus.ios --smoke-audio
container=$(xcrun simctl get_app_container "$device" org.readerplus.ios data)
for attempt in $(seq 1 180); do
  if [ -f "$container/Documents/audio-regression.json" ]; then break; fi
  sleep 1
done
cp "$container/Documents/audio-regression.json" build/compat-audio-regression.json
python3 -c 'import json; d=json.load(open("build/compat-audio-regression.json")); print(d); assert d["passed"],d'
python3 -c 'import subprocess,sys; f=open("build/compat-console.log","w"); subprocess.run(["xcrun","simctl","spawn",sys.argv[1],"log","show","--last","2m","--style","compact","--predicate","process == \"ReaderPlus\""],stdout=f,timeout=30)' "$device" || true
