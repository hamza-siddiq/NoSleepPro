#!/bin/bash
#
# Build a styled, drag-and-drop NoSleepPro.dmg (app + Applications shortcut).
# Run ./build.sh first so build/NoSleepPro.app exists.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/NoSleepPro.app"
VOL="NoSleep Pro"
DMG="$BUILD/NoSleepPro.dmg"
STAGING="$BUILD/dmg-staging"
TMP_DMG="$BUILD/nsp-rw.dmg"
MOUNT="/Volumes/$VOL"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first."; exit 1; }

echo "▸ Preparing staging folder…"
# Detach any stale mount, clean previous artifacts.
hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
rm -rf "$STAGING" "$DMG" "$TMP_DMG"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/NoSleepPro.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ Rendering background…"
swift "$ROOT/Icon/generate_dmg_background.swift" "$STAGING/.background/background.png" >/dev/null

echo "▸ Creating writable image…"
hdiutil create -srcfolder "$STAGING" -volname "$VOL" -fs HFS+ \
  -format UDRW -o "$TMP_DMG" >/dev/null

echo "▸ Mounting & styling…"
hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen >/dev/null

# Give it the app's own icon as the volume icon (best-effort).
if cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns" 2>/dev/null; then
  SetFile -a C "$MOUNT" 2>/dev/null || true
fi

# Lay out the Finder window. Best-effort: if the GUI/Finder isn't scriptable, the DMG is
# still a fully functional drag-and-drop installer, just without the custom layout.
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "  (Finder styling skipped — DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "NoSleepPro.app" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
echo "▸ Finalizing (compressed)…"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGING"

SIZE=$(du -h "$DMG" | cut -f1 | tr -d ' ')
echo "✓ Built $DMG ($SIZE)"
