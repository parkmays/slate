#!/usr/bin/env bash
# Run web portal checks from repo root. Optional production deploy via Vercel CLI.
#
# Usage:
#   bash scripts/release-web.sh
#   VERCEL_PROD=1 VERCEL_TOKEN=... bash scripts/release-web.sh
#
# CI parity: npm run type-check, lint, test, build (see apps/web/package.json).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/apps/web"

if [[ ! -f "$WEB_DIR/package.json" ]]; then
  echo "Expected web app at $WEB_DIR" >&2
  exit 1
fi

cd "$WEB_DIR"

echo "==> Installing dependencies (npm ci)"
npm ci

echo "==> Type check"
npm run type-check

echo "==> Lint"
npm run lint

echo "==> Unit tests"
npm run test

echo "==> Production build"
npm run build

if [[ "${VERCEL_PROD:-0}" == "1" ]]; then
  if [[ -z "${VERCEL_TOKEN:-}" ]]; then
    echo "VERCEL_PROD=1 requires VERCEL_TOKEN" >&2
    exit 1
  fi
  echo "==> Vercel production deploy"
  if command -v vercel >/dev/null 2>&1; then
    vercel --prod --token "$VERCEL_TOKEN" --cwd "$WEB_DIR"
  else
    npx --yes vercel@latest --prod --token "$VERCEL_TOKEN" --cwd "$WEB_DIR"
  fi
else
  echo ""
  echo "Skipping Vercel deploy (set VERCEL_PROD=1 VERCEL_TOKEN=... to deploy)."
  echo "GitHub Actions production deploy: .github/workflows/ci.yml deploy-web job on main."
fi
