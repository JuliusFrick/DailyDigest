#!/usr/bin/env bash
set -euo pipefail

# Generate appcast.xml for Sparkle updates
# Usage: VERSION=1.0.0 BUILD_NUMBER=1 DMG_URL=... ./scripts/generate-appcast.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DailyBriefing"
MACOS_VERSION="14.0"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
DMG_URL="${DMG_URL:-}"
DMG_PATH="${DMG_PATH:-dist/${APP_NAME}-${VERSION}.dmg}"
DMG_SIGNATURE="${DMG_SIGNATURE:-}"

if [[ -z "${VERSION}" || -z "${BUILD_NUMBER}" ]]; then
  echo "Error: VERSION and BUILD_NUMBER must be provided (e.g. VERSION=1.2.3 BUILD_NUMBER=42)" >&2
  exit 1
fi

if [[ -z "${DMG_URL}" ]]; then
  echo "Error: DMG_URL must be provided" >&2
  exit 1
fi

# Get file size if DMG exists locally
DMG_SIZE="0"
if [[ -f "${ROOT_DIR}/${DMG_PATH}" ]]; then
  DMG_SIZE=$(stat -f%z "${ROOT_DIR}/${DMG_PATH}")
fi

# Get current date in RSS format
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Read existing appcast.xml if it exists
APPCAST_PATH="${ROOT_DIR}/dist/appcast.xml"
EXISTING_ITEMS=""
if [[ -f "${APPCAST_PATH}" ]]; then
  # Extract existing items (everything between <channel> and </channel>, excluding the first item)
  EXISTING_ITEMS=$(sed -n '/<channel>/,/<\/channel>/p' "${APPCAST_PATH}" | sed '1d;$d' | grep -v '<item>' | grep -v '</item>' | head -n -1 || true)
fi

# Generate appcast.xml
mkdir -p "${ROOT_DIR}/dist"
cat > "${APPCAST_PATH}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="https://sparkle-project.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Updates</title>
    <link>https://juliusfrick.github.io/DailyDigest/appcast.xml</link>
    <description>Latest versions of ${APP_NAME}</description>
    <language>de</language>
    
    <item>
      <title>Version ${VERSION}</title>
      <link>https://github.com/juliusfrick/DailyBriefing</link>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MACOS_VERSION}</sparkle:minimumSystemVersion>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        <h2>Version ${VERSION}</h2>
        <p>Neue Version von ${APP_NAME}</p>
      ]]></description>
      <enclosure
        url="${DMG_URL}"
        length="${DMG_SIZE}"
        type="application/octet-stream"${DMG_SIGNATURE:+ sparkle:edSignature="${DMG_SIGNATURE}"} />
    </item>
${EXISTING_ITEMS}
  </channel>
</rss>
EOF

echo "✓ Generated appcast.xml at ${APPCAST_PATH}"
echo "  Version: ${VERSION}"
echo "  Build: ${BUILD_NUMBER}"
echo "  DMG URL: ${DMG_URL}"
