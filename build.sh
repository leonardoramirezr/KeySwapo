#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeySwapo"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
MIN_MACOS="15.0"
ARCH="${ARCH:-$(uname -m)}"
# "-" signs ad hoc. Use a stable identity (e.g. SIGN_IDENTITY="Apple Development") so macOS
# keeps the Accessibility permission across rebuilds; see README.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

echo "Compiling..."
xcrun swiftc \
    -parse-as-library \
    -O \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" \
    src/Core/*.swift src/App/*.swift \
    -framework AppKit \
    -framework SwiftUI \
    -framework Carbon \
    -framework ServiceManagement

cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
if [ -f Resources/Icon/AppIcon.icns ]; then
    cp Resources/Icon/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "Signing app..."
codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"

echo "Done: ${APP_BUNDLE}"
