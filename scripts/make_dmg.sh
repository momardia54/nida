#!/usr/bin/env bash
# Builds the app and wraps it in a drag-to-Applications DMG: dist/Nida-<version>.dmg
#   VERSION=1.0.0 ./scripts/make_dmg.sh
# For a notarized release (needs an Apple Developer account):
#   SIGN_ID="Developer ID Application: …" NOTARY_PROFILE=<keychain profile> ./scripts/make_dmg.sh
#   (create the profile once with: xcrun notarytool store-credentials <profile>)
#   or, e.g. in CI: NOTARY_APPLE_ID=… NOTARY_PASSWORD=<app-specific> NOTARY_TEAM_ID=… instead of NOTARY_PROFILE
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-1.0.0}
export VERSION
./scripts/build_app.sh
swift scripts/make_art.swift build/art >/dev/null

DMG=dist/Nida-$VERSION.dmg
STAGE=$(mktemp -d)
RW=$(mktemp -u).dmg
trap 'hdiutil detach "/Volumes/Nida" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW"' EXIT

echo "› Staging DMG contents"
ditto --noextattr --norsrc dist/Nida.app "$STAGE/Nida.app"
codesign --verify --strict "$STAGE/Nida.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
# Retina-aware background: one TIFF holding the 1x and 2x images
tiffutil -cathidpicheck build/art/dmg-background.png build/art/dmg-background@2x.png -out "$STAGE/.background/background.tiff" >/dev/null 2>&1

if [[ -d /Volumes/Nida ]] && ! hdiutil detach "/Volumes/Nida" -quiet 2>/dev/null; then
  echo "✗ A disk named Nida is mounted and in use (is Nida running from it?). Quit Nida and eject it, then retry." >&2
  exit 1
fi
# hdiutil occasionally reports "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3 4 5; do
  hdiutil create -srcfolder "$STAGE" -volname "Nida" -fs HFS+ -format UDRW -ov "$RW" >/dev/null && break
  [[ $attempt == 5 ]] && { echo "✗ hdiutil create failed" >&2; exit 1; }
  sleep 3
done
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "/Volumes/Nida" >/dev/null

# Volume icon
cp dist/Nida.app/Contents/Resources/AppIcon.icns "/Volumes/Nida/.VolumeIcon.icns"
SetFile -a C "/Volumes/Nida" 2>/dev/null || true

echo "› Laying out the window"
# Bounded to 90 s so a headless machine waiting on an Automation prompt can't hang the build.
if ! perl -e 'alarm 90; exec @ARGV' osascript <<'APPLESCRIPT' >/dev/null 2>&1
tell application "Finder"
  tell disk "Nida"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Nida.app" of container window to {170, 215}
    set position of item "Applications" of container window to {490, 215}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then
  echo "  ⚠ Finder layout skipped (allow Terminal to control Finder in System Settings › Privacy & Security › Automation). The DMG still works."
fi
sync
hdiutil detach "/Volumes/Nida" -quiet

echo "› Compressing"
rm -f "$DMG"
hdiutil convert "$RW" -format ULFO -o "$DMG" >/dev/null

if [[ -n ${SIGN_ID:-} && $SIGN_ID != - ]]; then
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG"
  if [[ -n ${NOTARY_PROFILE:-} ]]; then
    echo "› Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  elif [[ -n ${NOTARY_APPLE_ID:-} && -n ${NOTARY_PASSWORD:-} && -n ${NOTARY_TEAM_ID:-} ]]; then
    echo "› Notarizing"
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
      --team-id "$NOTARY_TEAM_ID" --wait
    xcrun stapler staple "$DMG"
  fi
fi
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
