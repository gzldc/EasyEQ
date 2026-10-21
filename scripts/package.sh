#!/usr/bin/env bash
# Usage: scripts/package.sh <version>
# Builds dist/EasyEQ.app via bundle.sh, then produces dist/EasyEQ-<version>.zip and .dmg.
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <version>   (e.g. 0.1.0)" >&2
  exit 64
fi
VERSION="$1"

cd "$(dirname "$0")/.."

scripts/bundle.sh

APP=dist/EasyEQ.app
ZIP="dist/EasyEQ-${VERSION}.zip"
DMG="dist/EasyEQ-${VERSION}.dmg"

# Stamp the release version into the bundle, then re-sign (editing Info.plist invalidates the signature).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG contents: the app plus an /Applications shortcut for drag-to-install.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname EasyEQ -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "Packaged:"
ls -lh "$ZIP" "$DMG"
