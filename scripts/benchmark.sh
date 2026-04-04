#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_FILE="${RESULTS_FILE:-$ROOT_DIR/benchmark-results.json}"

echo "🚀 Running SLATE package benchmarks..."

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to write benchmark JSON output."
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

printf '{"benchmarks":[]}\n' > "$RESULTS_FILE"

run_benchmark() {
  local name="$1"
  local threshold="$2"
  local workdir="$3"
  shift 3
  local output_file="$tmp_dir/$(echo "$name" | tr ' /' '__').log"

  echo "Running $name..."

  local elapsed
  if ! elapsed=$(python3 - "$workdir" "$output_file" "$@" <<'PY'
import pathlib
import subprocess
import sys
import time

workdir = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
command = sys.argv[3:]
start = time.perf_counter()
result = subprocess.run(command, cwd=workdir, capture_output=True, text=True)
elapsed = time.perf_counter() - start
output_path.write_text(result.stdout + result.stderr)
if result.returncode != 0:
    sys.stderr.write(output_path.read_text())
    sys.exit(result.returncode)
print(f"{elapsed:.3f}")
PY
  ); then
    echo "❌ $name failed"
    exit 1
  fi

  local passed="true"
  if python3 - "$elapsed" "$threshold" <<'PY'
import sys
elapsed = float(sys.argv[1])
threshold = float(sys.argv[2])
sys.exit(0 if elapsed <= threshold else 1)
PY
  then
    echo "✅ $name: ${elapsed}s"
  else
    echo "❌ $name: ${elapsed}s (threshold: ${threshold}s)"
    passed="false"
  fi

  local benchmark_json
  benchmark_json=$(jq -n \
    --arg name "$name" \
    --arg elapsed "$elapsed" \
    --arg threshold "$threshold" \
    --argjson passed "$passed" \
    '{
      name: $name,
      value: ($elapsed | tonumber),
      threshold: ($threshold | tonumber),
      unit: "seconds",
      passed: $passed,
      timestamp: (now | todate)
    }')

  jq --argjson benchmark "$benchmark_json" '.benchmarks += [$benchmark]' "$RESULTS_FILE" > "$tmp_dir/results.json"
  mv "$tmp_dir/results.json" "$RESULTS_FILE"

  if [ "$passed" = "false" ]; then
    return 1
  fi
}

run_benchmark "Sync Engine Test Suite" 30 "$ROOT_DIR/packages/sync-engine" swift test
run_benchmark "AI Pipeline Test Suite" 45 "$ROOT_DIR/packages/ai-pipeline" swift test
run_benchmark "Assembly Engine Benchmark" 5 "$ROOT_DIR/apps/desktop" env SLATE_RUN_BENCHMARKS=1 swift test --filter testAssemblyPerformanceBenchmark
run_benchmark "FCPXML Export Benchmark" 3 "$ROOT_DIR/packages/export-writers" env SLATE_RUN_BENCHMARKS=1 swift test --filter testFCPXMLExportBenchmark
run_benchmark "Sync Harness Script" 30 "$ROOT_DIR" ./scripts/test-sync.sh

failed="$(jq '[.benchmarks[] | select(.passed == false)] | length' "$RESULTS_FILE")"
if [ "$failed" -gt 0 ]; then
  echo ""
  echo "❌ $failed benchmark(s) failed."
  jq '.' "$RESULTS_FILE"
  exit 1
fi

echo ""
echo "✅ All benchmarks passed."
jq -r '.benchmarks[] | "\(.name): \(.value)s (threshold: \(.threshold)s)"' "$RESULTS_FILE"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "# Performance Benchmark Results"
    echo ""
    echo "| Benchmark | Result | Threshold | Status |"
    echo "|-----------|--------|-----------|--------|"
    jq -r '.benchmarks[] | "| \(.name) | \(.value) s | \(.threshold) s | \(if .passed then "✅ Passed" else "❌ Failed" end) |"' "$RESULTS_FILE"
  } >> "$GITHUB_STEP_SUMMARY"
fi
