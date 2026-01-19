#!/usr/bin/env bash
set -euo pipefail

# Create a professional "drag to Applications" DMG for DailyBriefing.
#
# This script:
# 1) Builds a release-style .app bundle into ./dist (via package-release.sh)
# 2) Creates a DMG with:
#    - DailyBriefing.app
#    - Applications symlink
#    - Nice layout and window settings
#
# Notes:
# - This does NOT sign or notarize. See README for signing/notarization steps.
# - Output goes to ./dist

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_NAME="DailyBriefing"
DIST_DIR="${ROOT_DIR}/dist"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

APP_DIR="${DIST_DIR}/${APP_NAME}.app"

DMG_ROOT="${DIST_DIR}/dmg-root"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
DMG_TEMP="${DIST_DIR}/${APP_NAME}-temp.dmg"

# 1) Build the .app bundle (and zip) into ./dist
VERSION="${VERSION}" BUILD_NUMBER="${BUILD_NUMBER}" "${ROOT_DIR}/scripts/package-release.sh"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Expected app bundle not found at: ${APP_DIR}" >&2
  exit 1
fi

# 2) Stage DMG contents
rm -rf "${DMG_ROOT}"
mkdir -p "${DMG_ROOT}"

cp -R "${APP_DIR}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

# 3) Create temporary DMG
rm -f "${DMG_TEMP}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "${DMG_TEMP}"

# 4) Mount the DMG
MOUNT_INFO=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_TEMP}" 2>&1)
MOUNT_POINT=$(echo "${MOUNT_INFO}" | awk '/^\/dev/ {for(i=3;i<=NF;i++) if($i ~ /^\/Volumes\//) {print $i; exit}}')

if [[ -z "${MOUNT_POINT}" ]]; then
  echo "Failed to mount DMG" >&2
  echo "Mount info: ${MOUNT_INFO}" >&2
  exit 1
fi

VOLUME_PATH="${MOUNT_POINT}"

# 5) Configure DMG window appearance (optional - skip if it causes issues)
# Try to set window size and position, but don't fail if it doesn't work
if osascript -e "tell application \"Finder\"" \
  -e "  tell disk \"${APP_NAME}\"" \
  -e "    open" \
  -e "    set current view of container window to icon view" \
  -e "    set toolbar visible of container window to false" \
  -e "    set statusbar visible of container window to false" \
  -e "    set the bounds of container window to {400, 100, 920, 420}" \
  -e "    set view options of container window to icon view options" \
  -e "    set arrangement of icon view options of container window to not arranged" \
  -e "    set icon size of icon view options of container window to 72" \
  -e "    delay 1" \
  -e "    try" \
  -e "      set position of item \"${APP_NAME}.app\" of container window to {160, 205}" \
  -e "    end try" \
  -e "    try" \
  -e "      set position of item \"Applications\" of container window to {360, 205}" \
  -e "    end try" \
  -e "    update without registering applications" \
  -e "    delay 2" \
  -e "  end tell" \
  -e "end tell" 2>/dev/null; then
  echo "DMG window configured"
else
  echo "Warning: Could not configure DMG window layout (this is optional)"
fi

# 6) Unmount the DMG
sleep 2
hdiutil detach "${MOUNT_POINT}" 2>/dev/null || hdiutil detach "${MOUNT_POINT}" -force 2>/dev/null || true
sleep 1

# 7) Convert to compressed read-only DMG
rm -f "${DMG_PATH}"
hdiutil convert "${DMG_TEMP}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "${DMG_PATH}"

# 8) Clean up
rm -f "${DMG_TEMP}"
rm -rf "${DMG_ROOT}"

echo ""
echo "✓ Created DMG: ${DMG_PATH}"
echo "  Size: $(du -h "${DMG_PATH}" | cut -f1)"
