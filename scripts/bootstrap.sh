#!/usr/bin/env bash
# SLATE — Full dev environment bootstrap
# Run once after cloning the repo.
# Requires: macOS 14+, Xcode 15+, Homebrew

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   SLATE — Dev Environment Bootstrap      ║"
echo "║   Mountain Top Pictures                  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Preflight checks ──────────────────────────────────────────────────────────
check() {
  if command -v "$1" &>/dev/null; then
    echo -e "${GREEN}✓${NC} $1 found"
  else
    echo -e "${RED}✗${NC} $1 not found — $2"
    MISSING+=("$1")
  fi
}

MISSING=()
check xcodebuild "Install Xcode 15+ from the Mac App Store"
check node "Install Node 20+ via https://nodejs.org or brew install node"
check npm "Comes with Node"
check supabase "brew install supabase/tap/supabase"
check deno "brew install deno"

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo -e "${RED}Missing dependencies: ${MISSING[*]}${NC}"
  echo "Please install the above and re-run bootstrap.sh"
  exit 1
fi

echo ""

# ── Validate contracts ────────────────────────────────────────────────────────
echo "▶ Validating contracts..."
bash "$(dirname "$0")/validate-contracts.sh"

# ── TypeScript shared types ───────────────────────────────────────────────────
echo ""
echo "▶ Installing TypeScript shared-types dependencies..."
cd packages/shared-types
npm install
npm run build
echo -e "${GREEN}✓${NC} shared-types compiled"
cd ../..

# ── Swift packages (resolve only — no build, that's Xcode's job) ─────────────
echo ""
echo "▶ Resolving Swift package dependencies..."

SWIFT_PKGS=(
  "packages/shared-types"
  "packages/ingest-daemon"
  "packages/export-writers"
)
# Codex and Gemini packages may not exist yet — skip gracefully
OPTIONAL_PKGS=(
  "packages/sync-engine"
  "packages/ai-pipeline"
)

for pkg in "${SWIFT_PKGS[@]}"; do
  if [ -f "$pkg/Package.swift" ]; then
    echo "  Resolving $pkg..."
    swift package --package-path "$pkg" resolve 2>&1 | tail -2
    echo -e "  ${GREEN}✓${NC} $pkg resolved"
  fi
done

for pkg in "${OPTIONAL_PKGS[@]}"; do
  if [ -f "$pkg/Package.swift" ]; then
    echo "  Resolving $pkg (optional)..."
    swift package --package-path "$pkg" resolve 2>&1 | tail -2
    echo -e "  ${GREEN}✓${NC} $pkg resolved"
  else
    echo -e "  ${YELLOW}⚠${NC} $pkg not yet created (waiting on Codex)"
  fi
done

# ── Supabase local stack ──────────────────────────────────────────────────────
echo ""
echo "▶ Starting Supabase local stack..."
if supabase status 2>/dev/null | grep -q "API URL"; then
  echo -e "${YELLOW}⚠${NC} Supabase already running — skipping start"
else
  supabase start
fi
echo -e "${GREEN}✓${NC} Supabase local stack ready"

# ── Run migrations ────────────────────────────────────────────────────────────
echo ""
echo "▶ Applying migrations..."
supabase db push --local 2>/dev/null || echo -e "${YELLOW}⚠${NC} No migrations yet (Gemini hasn't published them)"

# ── Seed dev data ─────────────────────────────────────────────────────────────
if [ -f "supabase/seed.sql" ] && grep -q "INSERT" supabase/seed.sql 2>/dev/null; then
  echo "▶ Seeding dev data..."
  supabase db reset --local
  echo -e "${GREEN}✓${NC} Dev data seeded"
fi

# ── Create required local directories ────────────────────────────────────────
echo ""
echo "▶ Creating SLATE application support directories..."
mkdir -p ~/Library/Application\ Support/SLATE
touch ~/Library/Application\ Support/SLATE/watchfolders.json
echo "[]" > ~/Library/Application\ Support/SLATE/watchfolders.json
mkdir -p ~/Movies/SLATE

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ${GREEN}Bootstrap complete!${NC}                     ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Build the desktop app: ./scripts/build-desktop-app.sh"
echo "  2. Open apps/web in your editor and run: cd apps/web && npm run dev"
echo "  3. Package a DMG when needed: ./scripts/package-desktop-dmg.sh"
echo "  4. Run ./scripts/benchmark.sh to check performance baselines"
echo ""
