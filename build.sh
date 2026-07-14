#!/bin/bash
#
# Build NoSleep Pro into a runnable, ad-hoc-signed .app bundle.
#
#   ./build.sh            # build into ./build/NoSleepPro.app
#   ./build.sh --install  # build, then copy to /Applications
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/NoSleepPro.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
DEPLOY_TARGET="13.0"
ARCH="$(uname -m)"

echo "▸ Cleaning…"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES"

echo "▸ Generating app icon…"
ICONSET="$BUILD/AppIcon.iconset"
swift "$ROOT/Icon/generate_icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

echo "▸ Compiling Swift sources ($ARCH, macOS $DEPLOY_TARGET)…"
swiftc \
  -O \
  -target "${ARCH}-apple-macosx${DEPLOY_TARGET}" \
  -framework AppKit \
  -framework IOKit \
  -framework ServiceManagement \
  -o "$MACOS_DIR/NoSleepPro" \
  "$ROOT/Sources/"*.swift

echo "▸ Assembling bundle…"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications…"
  rm -rf "/Applications/NoSleepPro.app"
  cp -R "$APP" "/Applications/NoSleepPro.app"
  echo "✓ Installed. Launch it from /Applications or Spotlight."
fi
