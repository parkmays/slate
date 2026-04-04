#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo "=== SLATE Sync Engine Tests ==="
cd "$ROOT/packages/sync-engine"
swift test --filter SLATESyncEngineTests 2>&1 | tee /tmp/sync-test.log
SYNC_EXIT=${PIPESTATUS[0]}

echo ""
echo "=== SLATE AI Pipeline Tests ==="
cd "$ROOT/packages/ai-pipeline"
swift test --filter SLATEAIPipelineTests 2>&1 | tee /tmp/ai-test.log
AI_EXIT=${PIPESTATUS[0]}

echo ""
if [ "$SYNC_EXIT" -eq 0 ] && [ "$AI_EXIT" -eq 0 ]; then
    echo "All tests passed."
    exit 0
else
    echo "Tests failed; see the logs above."
    exit 1
fi
