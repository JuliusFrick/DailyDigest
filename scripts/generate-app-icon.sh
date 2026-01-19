#!/usr/bin/env bash
set -euo pipefail

# Generate a macOS .icns file from a square PNG image.
# Usage: ./scripts/generate-app-icon.sh path/to/icon.png

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-square-png-icon>" >&2
  exit 1
fi

INPUT_PNG="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/assets"
OUTPUT_ICNS="${OUTPUT_DIR}/AppIcon.icns"

if [[ ! -f "${INPUT_PNG}" ]]; then
  echo "Error: Input file not found: ${INPUT_PNG}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# Create temporary directory for icon set (must end with .iconset)
ICONSET_DIR="${OUTPUT_DIR}/AppIcon.iconset"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"
trap "rm -rf '${ICONSET_DIR}'" EXIT

# Generate all required icon sizes
# macOS requires multiple sizes for different contexts
sips -z 16 16     "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${INPUT_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

# Convert iconset to icns
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"

echo "Created: ${OUTPUT_ICNS}"
