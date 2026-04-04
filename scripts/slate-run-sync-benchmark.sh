#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo "=== SLATE Sync Engine Benchmark ==="
echo "Running comprehensive sync accuracy tests..."
echo ""

cd "$ROOT/packages/sync-engine"
echo "Building and running sync benchmark tests..."
swift test -c release --filter SyncAccuracyBenchmark

# Check if results were generated
RESULTS_DIR="$ROOT/packages/sync-engine/Tests/SLATESyncEngineTests/Resources/BenchmarkData"
if [ -d "$RESULTS_DIR" ]; then
    echo ""
    echo "Benchmark results saved to: $RESULTS_DIR"
    echo "Latest report:"
    ls -t "$RESULTS_DIR"/SyncBenchmarkReport_*.json | head -1 | xargs -I {} sh -c 'echo "{}"; cat "{}"'
else
    echo "Warning: No results directory found"
fi

echo ""
echo "Benchmark complete!"
