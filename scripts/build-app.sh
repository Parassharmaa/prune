#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${1:-debug}"
APP="$ROOT/.build/Prune.app"

cd "$ROOT"
swift build -c "$CONFIGURATION"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/$CONFIGURATION/Prune" "$APP/Contents/MacOS/Prune"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "$APP"
