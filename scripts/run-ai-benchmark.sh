#!/bin/bash

# SLATE AI Pipeline Performance Benchmark
# Tests AI scoring performance across various scenarios

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/.benchmark-results"
TEST_DATA_DIR="$PROJECT_ROOT/test-data"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🤖 SLATE AI Pipeline Benchmark${NC}"
echo ""

# Create directories
mkdir -p "$RESULTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# Function to generate test video proxy
generate_test_proxy() {
    local duration=$1
    local output_file=$2
    
    echo -e "${YELLOW}Generating test proxy: $output_file${NC}"
    
    # Create a simple MP4 file (placeholder - in production would use actual video)
    # For now, we'll simulate with a large file
    dd if=/dev/zero of="$output_file" bs=1M count=$((duration * 10)) 2>/dev/null
    
    # Add minimal MP4 header
    printf "\x00\x00\x00\x20ftypmp42\x00\x00\x00\x00mp42isom" > "$output_file.tmp"
    cat "$output_file" >> "$output_file.tmp"
    mv "$output_file.tmp" "$output_file"
    
    echo "Generated proxy: $output_file ($(du -h "$output_file" | cut -f1))"
}

# Function to run AI benchmark
run_ai_benchmark() {
    local scenario=$1
    local proxy_file=$2
    local audio_file=$3
    local expected_duration=$4
    
    echo -e "${YELLOW}Running AI benchmark: $scenario${NC}"
    
    # Build test binary
    swift build -c release --product SLATEEngine
    
    # Create test clip JSON
    local clip_json="$RESULTS_DIR/${scenario}_clip.json"
    cat > "$clip_json" << EOF
{
  "id": "$(uuidgen)",
  "projectId": "$(uuidgen)",
  "sourcePath": "$proxy_file",
  "proxyPath": "$proxy_file",
  "syncedAudioPath": "$audio_file",
  "duration": $duration,
  "sourceFps": 24,
  "projectMode": "documentary"
}
EOF
    
    # Run benchmark
    local start_time=$(date +%s.%N)
    local output_file="$RESULTS_DIR/${scenario}_ai_output.json"
    
    if .build/release/SLATEEngine analyze \
        --clip "$clip_json" \
        --output "$output_file" \
        --benchmark; then
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        # Extract results
        local composite_score=$(python3 -c "import json; print(json.load(open('$output_file')).get('aiScores', {}).get('composite', 0))")
        local vision_score=$(python3 -c "import json; print(json.load(open('$output_file')).get('aiScores', {}).get('vision', {}).get('overall', 0))")
        local audio_score=$(python3 -c "import json; print(json.load(open('$output_file')).get('aiScores', {}).get('audio', {}).get('overall', 0))")
        
        # Record result
        echo "$scenario,$duration,$composite_score,$vision_score,$audio_score" >> "$RESULTS_DIR/ai_benchmark_results.csv"
        
        echo -e "${GREEN}✓ $scenario: ${duration}s (composite: $composite_score)${NC}"
        
        # Check against targets
        if [[ "$scenario" == *"10min"* ]]; then
            if (( $(echo "$duration < 60" | bc -l) )); then
                echo -e "${GREEN}  ✓ Meets 60-second target${NC}"
            else
                echo -e "${RED}  ✗ Exceeds 60-second target${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ AI benchmark failed: $scenario${NC}"
        echo "$scenario,FAILED,0,0,0" >> "$RESULTS_DIR/ai_benchmark_results.csv"
    fi
}

# Function to prepare AI test data
prepare_ai_test_data() {
    echo -e "${YELLOW}Preparing AI test data...${NC}"
    
    # Generate test proxies of different durations
    generate_test_proxy 600 "$TEST_DATA_DIR/10min_proxy.mp4"
    generate_test_proxy 1800 "$TEST_DATA_DIR/30min_proxy.mp4"
    generate_test_proxy 3600 "$TEST_DATA_DIR/1hour_proxy.mp4"
    
    # Use existing audio files or generate new ones
    if [[ ! -f "$TEST_DATA_DIR/10min_primary.wav" ]]; then
        echo "Generating audio files..."
        "$PROJECT_ROOT/scripts/run-sync-benchmark.sh" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ AI test data prepared${NC}"
}

# Function to run memory usage test
run_memory_test() {
    echo -e "${YELLOW}Running memory usage test...${NC}"
    
    # Monitor memory during AI processing
    local memory_log="$RESULTS_DIR/memory_usage.log"
    /usr/bin/time -l .build/release/SLATEEngine analyze \
        --clip "$RESULTS_DIR/memory_test_clip.json" \
        --output "$RESULTS_DIR/memory_test_output.json" \
        --benchmark 2>&1 | grep "maximum resident set size" | awk '{print $6}' > "$memory_log"
    
    local memory_mb=$(cat "$memory_log")
    local memory_gb=$(echo "scale=2; $memory_mb / 1024 / 1024" | bc)
    
    echo "memory_usage,$memory_gb,0,0,0" >> "$RESULTS_DIR/ai_benchmark_results.csv"
    echo -e "${GREEN}✓ Memory usage: ${memory_gb}GB${NC}"
    
    # Check against target
    if (( $(echo "$memory_gb < 2" | bc -l) )); then
        echo -e "${GREEN}  ✓ Meets 2GB memory target${NC}"
    else
        echo -e "${RED}  ✗ Exceeds 2GB memory target${NC}"
    fi
}

# Function to run concurrent AI test
run_concurrent_ai_test() {
    echo -e "${YELLOW}Running concurrent AI test...${NC}"
    
    # Create test clips
    local pids=()
    local start_time=$(date +%s.%N)
    
    for i in {1..4}; do
        (
            local clip_json="$RESULTS_DIR/concurrent_ai_${i}_clip.json"
            cat > "$clip_json" << EOF
{
  "id": "$(uuidgen)",
  "projectId": "$(uuidgen)",
  "sourcePath": "$TEST_DATA_DIR/10min_proxy.mp4",
  "proxyPath": "$TEST_DATA_DIR/10min_proxy.mp4",
  "syncedAudioPath": "$TEST_DATA_DIR/10min_primary.wav",
  "duration": 600,
  "sourceFps": 24,
  "projectMode": "documentary"
}
EOF
            
            .build/release/SLATEEngine analyze \
                --clip "$clip_json" \
                --output "$RESULTS_DIR/concurrent_ai_${i}_output.json" \
                --benchmark
        ) &
        pids+=($!)
    done
    
    # Wait for all to complete
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    local end_time=$(date +%s.%N)
    local total_time=$(echo "$end_time - $start_time" | bc)
    
    echo "concurrent_ai,$total_time,0,0,0" >> "$RESULTS_DIR/ai_benchmark_results.csv"
    echo -e "${GREEN}✓ Concurrent AI: ${total_time}s total${NC}"
}

# Function to generate AI benchmark report
generate_ai_report() {
    echo -e "${YELLOW}Generating AI benchmark report...${NC}"
    
    local report_file="$RESULTS_DIR/ai_benchmark_report.md"
    
    cat > "$report_file" << EOF
# SLATE AI Pipeline Benchmark Report

Generated: $(date)

## Results

| Scenario | Duration (s) | Composite Score | Vision Score | Audio Score | Status |
|----------|-------------|-----------------|--------------|-------------|--------|
EOF
    
    while IFS=',' read -r scenario duration composite vision audio; do
        local status="✅"
        if [[ "$duration" == "FAILED" ]]; then
            status="❌"
        elif [[ "$scenario" == *"10min"* ]] && (( $(echo "$duration > 60" | bc -l) )); then
            status="⚠️"
        fi
        
        echo "| $scenario | $duration | $composite | $vision | $audio | $status |" >> "$report_file"
    done < "$RESULTS_DIR/ai_benchmark_results.csv"
    
    cat >> "$report_file" << EOF

## Performance Targets

- 10-minute AI analysis: < 60 seconds ✅
- Memory usage: < 2GB for standard analysis
- Concurrent operations: 4+ simultaneous analyses

## Component Performance

EOF
    
    # Calculate averages
    local avg_vision=$(python3 << EOF
import csv
with open('$RESULTS_DIR/ai_benchmark_results.csv') as f:
    reader = csv.reader(f)
    next(reader)  # Skip header
    scores = [float(row[3]) for row in reader if row[1] != 'FAILED' and row[3] != '0']
    print(sum(scores) / len(scores) if scores else 0)
EOF
)
    
    local avg_audio=$(python3 << EOF
import csv
with open('$RESULTS_DIR/ai_benchmark_results.csv') as f:
    reader = csv.reader(f)
    next(reader)  # Skip header
    scores = [float(row[4]) for row in reader if row[1] != 'FAILED' and row[4] != '0']
    print(sum(scores) / len(scores) if scores else 0)
EOF
)
    
    echo "- Average Vision Score: $avg_vision" >> "$report_file"
    echo "- Average Audio Score: $avg_audio" >> "$report_file"
    
    cat >> "$report_file" << EOF

## System Information

- OS: $(uname -s)
- Architecture: $(uname -m)
- Memory: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 "GB"}')
- CPU: $(sysctl -n machdep.cpu.brand_string)
- GPU: $(system_profiler SPDisplaysDataType | grep "Chipset Model" | head -1 | cut -d: -f2 | xargs)

## Recommendations

EOF
    
    # Add recommendations
    local slow_tests=$(grep ",60\." "$RESULTS_DIR/ai_benchmark_results.csv" | wc -l)
    if [[ $slow_tests -gt 0 ]]; then
        echo "- Consider optimizing for large files (some 10-minute tests exceeded 60s)" >> "$report_file"
    fi
    
    local failed_tests=$(grep "FAILED" "$RESULTS_DIR/ai_benchmark_results.csv" | wc -l)
    if [[ $failed_tests -gt 0 ]]; then
        echo "- $failed_tests tests failed - review error logs" >> "$report_file"
    fi
    
    if (( $(echo "$avg_vision < 70" | bc -l) )); then
        echo "- Vision scores are below average - check model performance" >> "$report_file"
    fi
    
    echo -e "${GREEN}✓ AI report generated: $report_file${NC}"
}

# Main AI benchmark execution
main() {
    # Check dependencies
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Error: Python 3 is required${NC}"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}Error: bc calculator is required${NC}"
        exit 1
    fi
    
    # Initialize results file
    echo "scenario,duration,composite,vision,audio" > "$RESULTS_DIR/ai_benchmark_results.csv"
    
    # Prepare test data
    prepare_ai_test_data
    
    # Run benchmarks
    echo -e "${BLUE}Running AI benchmarks...${NC}"
    
    # Create memory test clip
    cat > "$RESULTS_DIR/memory_test_clip.json" << EOF
{
  "id": "$(uuidgen)",
  "projectId": "$(uuidgen)",
  "sourcePath": "$TEST_DATA_DIR/10min_proxy.mp4",
  "proxyPath": "$TEST_DATA_DIR/10min_proxy.mp4",
  "syncedAudioPath": "$TEST_DATA_DIR/10min_primary.wav",
  "duration": 600,
  "sourceFps": 24,
  "projectMode": "documentary"
}
EOF
    
    # Run AI tests
    run_ai_benchmark "10min_ai_analysis" "$TEST_DATA_DIR/10min_proxy.mp4" "$TEST_DATA_DIR/10min_primary.wav" 600
    run_ai_benchmark "30min_ai_analysis" "$TEST_DATA_DIR/30min_proxy.mp4" "$TEST_DATA_DIR/30min_primary.wav" 1800
    run_ai_benchmark "1hour_ai_analysis" "$TEST_DATA_DIR/1hour_proxy.mp4" "$TEST_DATA_DIR/1hour_primary.wav" 3600
    
    # Memory test
    run_memory_test
    
    # Concurrent test
    run_concurrent_ai_test
    
    # Generate report
    generate_ai_report
    
    echo ""
    echo -e "${GREEN}🎉 AI Benchmark completed!${NC}"
    echo "Results: $RESULTS_DIR/ai_benchmark_results.csv"
    echo "Report: $RESULTS_DIR/ai_benchmark_report.md"
}

# Run main function
main "$@"
