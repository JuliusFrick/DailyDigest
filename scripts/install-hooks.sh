#!/usr/bin/env bash
# Install git hooks for pre-commit checks.
# Run: ./scripts/install-hooks.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_SRC="${ROOT_DIR}/.githooks"
HOOKS_DEST="${ROOT_DIR}/.git/hooks"

mkdir -p "${HOOKS_DEST}"
for hook in pre-commit; do
  if [[ -f "${HOOKS_SRC}/${hook}" ]]; then
    cp "${HOOKS_SRC}/${hook}" "${HOOKS_DEST}/${hook}"
    chmod +x "${HOOKS_DEST}/${hook}"
    echo "Installed ${hook} hook"
  fi
done
echo "Done. Pre-commit will run release build check before each commit."
