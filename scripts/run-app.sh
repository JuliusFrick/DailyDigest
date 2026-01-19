#!/usr/bin/env bash
set -euo pipefail

# Build and run DailyBriefing as a proper .app bundle.
# This is required for certain macOS APIs (e.g. UserNotifications) that expect an app bundle.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${ROOT_DIR}/DailyBriefing"
ASSETS_DIR="${ROOT_DIR}/assets"

APP_NAME="DailyBriefing"
APP_DIR="${PKG_DIR}/.build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
ICON_ICNS="${ROOT_DIR}/assets/AppIcon.icns"

SOURCE_ICON_PNG="${SOURCE_ICON_PNG:-/Users/julius.frick/Downloads/Gemini_Generated_Image_qvpmarqvpmarqvpm.png}"
SOURCE_ICON_VERTICAL_PNG="${SOURCE_ICON_VERTICAL_PNG:-/Users/julius.frick/Downloads/VERT_Gemini_Generated_Image_z36h4wz36h4wz36h.png}"

SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://juliusfrick.github.io/DailyBriefing/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

SPARKLE_PLIST_KEYS=""
if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
  SPARKLE_PLIST_KEYS="$(cat <<EOF
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_ED_KEY}</string>
EOF
)"
fi

pushd "${PKG_DIR}" >/dev/null

write_oauth_clients() {
  local target_path="${RESOURCES_DIR}/oauth_clients.json"

  if [[ -n "${OAUTH_CLIENTS_JSON_PATH:-}" && -f "${OAUTH_CLIENTS_JSON_PATH}" ]]; then
    cp -f "${OAUTH_CLIENTS_JSON_PATH}" "${target_path}"
    return
  fi

  if [[ -n "${OAUTH_CLIENTS_JSON:-}" ]]; then
    printf '%s' "${OAUTH_CLIENTS_JSON}" > "${target_path}"
    return
  fi

  if [[ -z "${OAUTH_GOOGLE_CLIENT_ID:-}" && -z "${OAUTH_GOOGLE_CLIENT_SECRET:-}" \
     && -z "${OAUTH_SLACK_CLIENT_ID:-}" && -z "${OAUTH_SLACK_CLIENT_SECRET:-}" \
     && -z "${OAUTH_JIRA_CLIENT_ID:-}" && -z "${OAUTH_JIRA_CLIENT_SECRET:-}" ]]; then
    return
  fi

  cat > "${target_path}" <<EOF
{
  "google": {
    "clientId": "${OAUTH_GOOGLE_CLIENT_ID:-}",
    "clientSecret": "${OAUTH_GOOGLE_CLIENT_SECRET:-}"
  },
  "slack": {
    "clientId": "${OAUTH_SLACK_CLIENT_ID:-}",
    "clientSecret": "${OAUTH_SLACK_CLIENT_SECRET:-}"
  },
  "jira": {
    "clientId": "${OAUTH_JIRA_CLIENT_ID:-}",
    "clientSecret": "${OAUTH_JIRA_CLIENT_SECRET:-}"
  }
}
EOF
}

# Refresh app icons from the latest source images when available.
mkdir -p "${ASSETS_DIR}"
if [[ -f "${SOURCE_ICON_PNG}" ]]; then
  "${ROOT_DIR}/scripts/generate-app-icon.sh" "${SOURCE_ICON_PNG}"
  cp -f "${SOURCE_ICON_PNG}" "${ASSETS_DIR}/icon.png"
fi
if [[ -f "${SOURCE_ICON_VERTICAL_PNG}" ]]; then
  cp -f "${SOURCE_ICON_VERTICAL_PNG}" "${ASSETS_DIR}/icon-vertical.png"
fi

swift build

BIN_PATH="${PKG_DIR}/.build/debug/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Expected build product not found at: ${BIN_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp -f "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Copy Sparkle.framework to app bundle
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
mkdir -p "${FRAMEWORKS_DIR}"

# Find Sparkle.framework in build directory (prefer architecture-specific, fallback to xcframework)
SPARKLE_FRAMEWORK=""
if [[ -d "${PKG_DIR}/.build/arm64-apple-macosx/debug/Sparkle.framework" ]]; then
  SPARKLE_FRAMEWORK="${PKG_DIR}/.build/arm64-apple-macosx/debug/Sparkle.framework"
elif [[ -d "${PKG_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]]; then
  SPARKLE_FRAMEWORK="${PKG_DIR}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi

if [[ -n "${SPARKLE_FRAMEWORK}" && -d "${SPARKLE_FRAMEWORK}" ]]; then
  echo "Copying Sparkle.framework from ${SPARKLE_FRAMEWORK}"
  cp -R "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
  
  # Update rpath in the binary to include Frameworks directory
  install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true
else
  echo "Warning: Sparkle.framework not found. App may crash at launch." >&2
fi

# Optional app icon
if [[ -f "${ICON_ICNS}" ]]; then
  cp -f "${ICON_ICNS}" "${RESOURCES_DIR}/AppIcon.icns"
fi

write_oauth_clients

cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>de</string>
  <key>CFBundleExecutable</key>
  <string>DailyBriefing</string>
  <key>CFBundleIdentifier</key>
  <string>com.juliusfrick.dailybriefing</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DailyBriefing</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.juliusfrick.dailybriefing</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>dailybriefing</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUEnableAutomaticChecks</key>
  <false/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
${SPARKLE_PLIST_KEYS}
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSRemindersUsageDescription</key>
  <string>DailyBriefing benötigt Zugriff auf Erinnerungen, um deine Aufgaben im Briefing anzuzeigen.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>DailyBriefing benötigt Automation-Zugriff, um Apple Mail auszulesen und E-Mails im Briefing anzuzeigen.</string>
</dict>
</plist>
PLIST

# Re-sign the app bundle with ad-hoc signature
# This is critical after copying frameworks to ensure the app can launch
echo "Signing app bundle..."
codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1

echo "Launching: ${APP_DIR}"
open -n "${APP_DIR}"

popd >/dev/null

