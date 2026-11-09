#!/bin/bash
# Nabız.app paketini derler ve ad-hoc imzalar.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Nabiz"

APP="build/Nabız.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nabiz"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Hazır: $APP"
