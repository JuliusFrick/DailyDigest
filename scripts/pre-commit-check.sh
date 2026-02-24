#!/usr/bin/env bash
# Pre-commit check: Runs the same build + package steps as the Release workflow.
# Run this before committing to catch CI failures locally.
# Usage: ./scripts/pre-commit-check.sh [--no-dmg]
#   --no-dmg: Skip DMG creation (faster, still validates build + app bundle)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${ROOT_DIR}/DailyBriefing"
APP_NAME="DailyBriefing"
VERSION="0.0.0-dev"
BUILD_NUMBER="1"

SKIP_DMG=false
for arg in "$@"; do
  case "$arg" in
    --no-dmg) SKIP_DMG=true ;;
  esac
done

echo "=== Pre-commit check: Release build simulation ==="
echo ""

# Step 1: Package app bundle (includes swift build - same as CI)
echo "[1/2] package-release.sh (build + app bundle)..."
VERSION="${VERSION}" \
BUILD_NUMBER="${BUILD_NUMBER}" \
REQUIRE_SPARKLE_PUBLIC_ED_KEY="" \
SPARKLE_PUBLIC_ED_KEY="" \
"${ROOT_DIR}/scripts/package-release.sh"
echo "✓ App bundle OK"
echo ""

# Step 2: Create DMG (optional, validates full pipeline)
if [[ "$SKIP_DMG" == "true" ]]; then
  echo "[2/2] DMG creation skipped (--no-dmg)"
else
  echo "[2/2] package-dmg.sh..."
  VERSION="${VERSION}" \
  BUILD_NUMBER="${BUILD_NUMBER}" \
  "${ROOT_DIR}/scripts/package-dmg.sh"
  echo "✓ DMG OK"
fi

echo ""
echo "=== Pre-commit check passed ==="
echo "Release pipeline would succeed in CI."
