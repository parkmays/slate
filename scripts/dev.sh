#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting the SLATE development environment..."
echo "Desktop app: use swift run/build in apps/desktop, or ./scripts/build-desktop-app.sh for a packaged .app."
echo "Web portal: delegating to scripts/dev-web.sh."
echo ""

"$SCRIPT_DIR/dev-web.sh"
