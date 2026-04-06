#!/usr/bin/env bash
# Canonical root SwiftPM build: shared-types first, then full graph + tests.
# Use this when `swift build` at the repo root fails without a prior package build.
#
# Usage: ./scripts/build-root-swift.sh [release|debug]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${1:-release}"

echo "==> SLATESharedTypes ($CFG)"
(cd "$ROOT_DIR/packages/shared-types" && swift build -c "$CFG")

echo "==> Root SLATEEngine package ($CFG)"
cd "$ROOT_DIR"
swift build -c "$CFG"

echo "==> Root tests ($CFG)"
swift test -c "$CFG"
