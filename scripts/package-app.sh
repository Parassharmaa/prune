#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
ARM_BUILD="$ROOT/.build/package-arm64"
INTEL_BUILD="$ROOT/.build/package-x86_64"
APP="$ROOT/.build/Prune.app"
DIST="$ROOT/.build/dist"
ARCHIVE="$DIST/Prune-macOS.zip"

cd "$ROOT"

swift build -c release --arch arm64 --build-path "$ARM_BUILD"
swift build -c release --arch x86_64 --build-path "$INTEL_BUILD"

rm -rf "$APP" "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"

lipo -create \
  "$ARM_BUILD/release/Prune" \
  "$INTEL_BUILD/release/Prune" \
  -output "$APP/Contents/MacOS/Prune"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/Prune")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
(
  cd "$DIST"
  shasum -a 256 "${ARCHIVE:t}" > "${ARCHIVE:t}.sha256"
)

echo "$ARCHIVE"
