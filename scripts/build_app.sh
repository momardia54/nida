#!/usr/bin/env bash
# Builds dist/Nida.app (universal when possible).
#   VERSION=1.0.0 BUILD=1 ./scripts/build_app.sh
# Optional signing for distribution:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)"   (default: ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-1.0.0}
BUILD=${BUILD:-1}
SIGN_ID=${SIGN_ID:--}
# Assemble and sign outside the Desktop: iCloud Drive's sync adds extended attributes
# that codesign rejects. The signed bundle is then copied into dist/.
STAGE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/nida-build.XXXXXX")
trap 'rm -rf "$STAGE_ROOT"' EXIT
APP=$STAGE_ROOT/Nida.app

echo "› Building Nida $VERSION ($BUILD)"
if [[ ! -f Resources/Sounds/adhan-classic.m4a ]]; then
  ./scripts/prepare_audio.sh
fi

# Universal binary: build each architecture, then merge.
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/arm64 >/dev/null
ARM=.build/arm64/release/Nida
if swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/x86_64 >/dev/null 2>&1; then
  X86=.build/x86_64/release/Nida
  mkdir -p .build/universal
  lipo -create "$ARM" "$X86" -output .build/universal/Nida
  BIN=.build/universal/Nida
  echo "  universal binary (arm64 + x86_64)"
else
  BIN=$ARM
  echo "  arm64 binary (x86_64 build unavailable)"
fi

echo "› Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"
cp "$BIN" "$APP/Contents/MacOS/Nida"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/Sounds/*.m4a Resources/Sounds/*.json "$APP/Contents/Resources/Sounds/"

if [[ ! -f build/art/AppIcon.iconset/icon_512x512@2x.png ]]; then
  swift scripts/make_art.swift build/art
fi
iconutil -c icns build/art/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
echo "› Signing ($([[ $SIGN_ID == - ]] && echo ad-hoc || echo "$SIGN_ID"))"
if [[ $SIGN_ID == - ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$APP"
fi
codesign --verify --strict "$APP"
mkdir -p dist
rm -rf dist/Nida.app
ditto --noextattr --norsrc "$APP" dist/Nida.app
echo "✓ dist/Nida.app"
