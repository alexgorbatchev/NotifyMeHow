#!/usr/bin/env bash
# Creates a macOS app bundle from the built executable

set -euo pipefail

APP_NAME="NotifyMeHow"
CONFIG="${1:-release}"
APP_DIR="${2:-${APP_NAME}.app}"
# Ad-hoc signing ("-") is trusted per binary, so macOS forgets Accessibility
# permission on every rebuild; a real identity keeps it across rebuilds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

echo "Building ${APP_NAME} (${CONFIG})..."
swift build -c "${CONFIG}"
BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"

echo "Creating app bundle at ${APP_DIR}..."
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/Fonts"

cp -f "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

cp -f "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp -f "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"
cp -f "Resources/MenuBarIcon.png" "${APP_DIR}/Contents/Resources/"
cp -f "Resources/MenuBarIcon@2x.png" "${APP_DIR}/Contents/Resources/"
cp -f Resources/Fonts/* "${APP_DIR}/Contents/Resources/Fonts/"

codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"

echo "App bundle created: ${APP_DIR}"
