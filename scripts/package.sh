#!/usr/bin/env bash
# Usage: scripts/package.sh <version>
# Builds dist/EasyEQ.app via bundle.sh, then produces dist/EasyEQ-<version>.zip and .dmg
# (the DMG needs dmgbuild: pip install dmgbuild).
set -euo pipefail

usage() {
  echo "usage: $0 <version>   (X.Y.Z, optionally with a suffix: 0.2.0, 0.2.0-beta.1, 0.0.0-test.7)" >&2
  exit 64
}
[ $# -eq 1 ] || usage
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.+][0-9A-Za-z.-]+)?$ ]] || usage
# CFBundleShortVersionString must be plain numeric X.Y.Z; the full string (with any suffix) goes in CFBundleVersion.
SHORT_VERSION="$(echo "$VERSION" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"

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
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${SHORT_VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"
sign_app "$APP"
codesign --verify --deep --strict "$APP"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"

# Styled drag-to-install DMG (window layout, background and volume icon: scripts/dmg-settings.py).
# dmgbuild writes the .DS_Store itself, so this works headless (CI) without Finder.
"${DMGBUILD[@]}" -s scripts/dmg-settings.py -D app="$APP" EasyEQ "$DMG"

echo "Packaged:"
ls -lh "$ZIP" "$DMG"
