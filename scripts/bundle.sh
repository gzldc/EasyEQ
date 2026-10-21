#!/usr/bin/env bash
# Builds a universal release binary and assembles dist/EasyEQ.app (ad-hoc signed unless SIGN_IDENTITY is set).
set -euo pipefail

cd "$(dirname "$0")/.."

APP=dist/EasyEQ.app

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/EasyEQ" "$APP/Contents/MacOS/EasyEQ"
cp Resources/AppBundle/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/AppBundle/en.lproj Resources/AppBundle/zh-Hans.lproj "$APP/Contents/Resources/"
# Localizer.resourceBundle() looks for this bundle in Contents/Resources.
cp -R "$BIN_DIR/EasyEQ_EasyEQCore.bundle" "$APP/Contents/Resources/"

codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
