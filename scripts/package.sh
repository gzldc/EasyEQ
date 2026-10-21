#!/usr/bin/env bash
# Usage: scripts/package.sh <version>
# Builds dist/EasyEQ.app via bundle.sh, then produces dist/EasyEQ-<version>.zip and .dmg
# (the DMG needs dmgbuild: pip install dmgbuild).
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <version>   (e.g. 0.1.0)" >&2
  exit 64
fi
VERSION="$1"

cd "$(dirname "$0")/.."

# dmgbuild is checked first so a missing install fails before the long build.
if command -v dmgbuild >/dev/null 2>&1; then
  DMGBUILD=(dmgbuild)
elif python3 -c "import dmgbuild" >/dev/null 2>&1; then
  DMGBUILD=(python3 -m dmgbuild)
else
  echo "error: dmgbuild not found. Install it with:" >&2
  echo "  python3 -m venv .build/dmgvenv && .build/dmgvenv/bin/pip install dmgbuild && export PATH=\"\$PWD/.build/dmgvenv/bin:\$PATH\"" >&2
  echo "  (or: pip install dmgbuild)" >&2
  exit 69
fi

scripts/bundle.sh

source scripts/sign.sh

APP=dist/EasyEQ.app
ZIP="dist/EasyEQ-${VERSION}.zip"
DMG="dist/EasyEQ-${VERSION}.dmg"

# Stamp the release version into the bundle, then re-sign (editing Info.plist invalidates the signature).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
sign_app "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# Styled drag-to-install DMG (window layout, background and volume icon: scripts/dmg-settings.py).
# dmgbuild writes the .DS_Store itself, so this works headless (CI) without Finder.
"${DMGBUILD[@]}" -s scripts/dmg-settings.py -D app="$APP" EasyEQ "$DMG"

echo "Packaged:"
ls -lh "$ZIP" "$DMG"
