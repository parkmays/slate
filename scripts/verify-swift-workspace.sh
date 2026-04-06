#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export LC_ALL=C
export LANG=C
export TZ=UTC

# shared-types first (matches scripts/build-root-swift.sh) so root/desktop graphs see a warm module.
PACKAGES=(
  "packages/shared-types"
  "."
  "apps/desktop"
  "packages/sync-engine"
  "packages/ai-pipeline"
  "packages/ingest-daemon"
  "packages/export-writers"
)

echo "== SLATE deterministic Swift verification =="
echo "Root: $ROOT_DIR"
echo "Packages: ${#PACKAGES[@]}"

for pkg in "${PACKAGES[@]}"; do
  echo ""
  echo "== Verifying $pkg =="
  (
    cd "$pkg"
    swift package clean
    swift build
    swift test
  )
done

echo ""
echo "All Swift package builds/tests passed."
