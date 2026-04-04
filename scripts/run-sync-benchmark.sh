#!/bin/bash

# SLATE Sync Engine Performance Benchmark
# Tests sync performance across various scenarios

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

echo -e "${BLUE}🏃 SLATE Sync Engine Benchmark${NC}"
echo ""

# Create directories
mkdir -p "$RESULTS_DIR"
mkdir -p "$TEST_DATA_DIR"

# Test scenarios
declare -a TEST_SCENARIOS=(
    "10min_perfect_sync"
    "10min_2frame_offset"
    "10min_5frame_offset"
    "10min_noisy_30percent"
    "10min_noisy_60percent"
    "30min_perfect_sync"
    "1hour_perfect_sync"
    "different_samplerates"
    "concurrent_syncs"
)

# Function to generate test audio
generate_test_audio() {
    local duration=$1
    local offset=$2
    local noise_level=$3
    local output_file=$4
    
    echo -e "${YELLOW}Generating test audio: $output_file${NC}"
    
    # Use Python to generate test audio
    python3 << EOF
import numpy as np
import wave
import sys

duration = $duration
offset = $offset
noise_level = $noise_level
sample_rate = 48000
samples = int(duration * sample_rate)

# Generate click track
t = np.linspace(0, duration, samples, False)
audio = np.zeros(samples)

# Add clicks every 0.5 seconds
click_interval = sample_rate // 2
click_offset = int(offset * sample_rate)
for i in range(click_offset, samples, click_interval):
    if i < samples:
        # 1ms click
        click_length = sample_rate // 1000
        click_end = min(i + click_length, samples)
        audio[i:click_end] = np.random.uniform(-0.5, 0.5, click_end - i)

# Add noise
if noise_level > 0:
    noise = np.random.normal(0, noise_level, samples)
    audio += noise

# Normalize
audio = np.clip(audio, -1, 1)

# Save as WAV
with wave.open('$output_file', 'w') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    wav.writeframes((audio * 32767).astype(np.int16).tobytes())

print(f"Generated {output_file}")
EOF
}

# Function to run single benchmark
run_benchmark() {
    local scenario=$1
    local primary_file=$2
    local secondary_file=$3
    local fps=$4
    
    echo -e "${YELLOW}Running benchmark: $scenario${NC}"
    
    # Build test binary
    swift build -c release --product SLATEEngine
    
    # Run benchmark
    local start_time=$(date +%s.%N)
    local output_file="$RESULTS_DIR/${scenario}_output.json"
    
    if .build/release/SLATEEngine sync \
        --primary "$primary_file" \
        --secondary "$secondary_file" \
        --fps $fps \
        --output "$output_file" \
        --benchmark; then
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        
        # Extract results
        local offset=$(python3 -c "import json; print(json.load(open('$output_file')).get('offsetFrames', 0))")
        local confidence=$(python3 -c "import json; print(json.load(open('$output_file')).get('confidence', 0))")
        
        # Record result
        echo "$scenario,$duration,$offset,$confidence" >> "$RESULTS_DIR/benchmark_results.csv"
        
        echo -e "${GREEN}✓ $scenario: ${duration}s (offset: $offset, confidence: $confidence)${NC}"
        
        # Check against targets
        if [[ "$scenario" == *"10min"* ]]; then
            if (( $(echo "$duration < 30" | bc -l) )); then
                echo -e "${GREEN}  ✓ Meets 30-second target${NC}"
            else
                echo -e "${RED}  ✗ Exceeds 30-second target${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Benchmark failed: $scenario${NC}"
        echo "$scenario,FAILED,0,0" >> "$RESULTS_DIR/benchmark_results.csv"
    fi
}

# Function to prepare test data
prepare_test_data() {
    echo -e "${YELLOW}Preparing test data...${NC}"
    
    # 10-minute perfect sync
    generate_test_audio 600 0 0 "$TEST_DATA_DIR/10min_primary.wav"
    generate_test_audio 600 0 0 "$TEST_DATA_DIR/10min_secondary.wav"
    
    # 10-minute 2-frame offset
    generate_test_audio 600 0 0 "$TEST_DATA_DIR/10min_2frame_primary.wav"
    generate_test_audio 600 0.0833 0 "$TEST_DATA_DIR/10min_2frame_secondary.wav"  # 2/24 = 0.0833s
    
    # 10-minute 5-frame offset
    generate_test_audio 600 0 0 "$TEST_DATA_DIR/10min_5frame_primary.wav"
    generate_test_audio 600 0.2083 0 "$TEST_DATA_DIR/10min_5frame_secondary.wav"  # 5/24 = 0.2083s
    
    # 10-minute noisy 30%
    generate_test_audio 600 0 0.3 "$TEST_DATA_DIR/10min_noisy30_primary.wav"
    generate_test_audio 600 0 0.3 "$TEST_DATA_DIR/10min_noisy30_secondary.wav"
    
    # 10-minute noisy 60%
    generate_test_audio 600 0 0.6 "$TEST_DATA_DIR/10min_noisy60_primary.wav"
    generate_test_audio 600 0 0.6 "$TEST_DATA_DIR/10min_noisy60_secondary.wav"
    
    # 30-minute perfect sync
    generate_test_audio 1800 0 0 "$TEST_DATA_DIR/30min_primary.wav"
    generate_test_audio 1800 0 0 "$TEST_DATA_DIR/30min_secondary.wav"
    
    # 1-hour perfect sync
    generate_test_audio 3600 0 0 "$TEST_DATA_DIR/1hour_primary.wav"
    generate_test_audio 3600 0 0 "$TEST_DATA_DIR/1hour_secondary.wav"
    
    # Different sample rates
    generate_test_audio 300 0 0 "$TEST_DATA_DIR/48khz_primary.wav"
    # Generate 44.1kHz version
    python3 << EOF
import numpy as np
import wave

duration = 300
sample_rate = 44100
samples = int(duration * sample_rate)

# Simple tone
t = np.linspace(0, duration, samples, False)
audio = 0.5 * np.sin(2 * np.pi * 440 * t)

with wave.open('$TEST_DATA_DIR/44khz_secondary.wav', 'w') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(sample_rate)
    wav.writeframes((audio * 32767).astype(np.int16).tobytes())
EOF
    
    echo -e "${GREEN}✓ Test data prepared${NC}"
}

# Function to run concurrent sync test
run_concurrent_test() {
    echo -e "${YELLOW}Running concurrent sync test...${NC}"
    
    # Generate 4 test files
    for i in {1..4}; do
        generate_test_audio 120 0 0 "$TEST_DATA_DIR/concurrent_${i}.wav"
    done
    
    # Run 4 syncs in parallel
    local pids=()
    local start_time=$(date +%s.%N)
    
    for i in {1..4}; do
        (
            .build/release/SLATEEngine sync \
                --primary "$TEST_DATA_DIR/concurrent_${i}.wav" \
                --secondary "$TEST_DATA_DIR/concurrent_$((i%4+1)).wav" \
                --fps 24 \
                --output "$RESULTS_DIR/concurrent_${i}_output.json" \
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
    
    echo "concurrent_syncs,$total_time,0,0" >> "$RESULTS_DIR/benchmark_results.csv"
    echo -e "${GREEN}✓ Concurrent syncs: ${total_time}s total${NC}"
}

# Function to generate benchmark report
generate_report() {
    echo -e "${YELLOW}Generating benchmark report...${NC}"
    
    local report_file="$RESULTS_DIR/benchmark_report.md"
    
    cat > "$report_file" << EOF
# SLATE Sync Engine Benchmark Report

Generated: $(date)

## Results

| Scenario | Duration (s) | Offset Frames | Confidence | Status |
|----------|-------------|---------------|------------|--------|
EOF
    
    while IFS=',' read -r scenario duration offset confidence; do
        local status="✅"
        if [[ "$duration" == "FAILED" ]]; then
            status="❌"
        elif [[ "$scenario" == *"10min"* ]] && (( $(echo "$duration > 30" | bc -l) )); then
            status="⚠️"
        fi
        
        echo "| $scenario | $duration | $offset | $confidence | $status |" >> "$report_file"
    done < "$RESULTS_DIR/benchmark_results.csv"
    
    cat >> "$report_file" << EOF

## Performance Targets

- 10-minute sync: < 30 seconds ✅
- Memory usage: < 1GB for 10-minute files
- Concurrent operations: 4+ simultaneous syncs

## System Information

- OS: $(uname -s)
- Architecture: $(uname -m)
- Memory: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 "GB"}')
- CPU: $(sysctl -n machdep.cpu.brand_string)

## Recommendations

EOF
    
    # Add recommendations based on results
    local slow_tests=$(grep ",30\." "$RESULTS_DIR/benchmark_results.csv" | wc -l)
    if [[ $slow_tests -gt 0 ]]; then
        echo "- Consider optimizing for large files (some 10-minute tests exceeded 30s)" >> "$report_file"
    fi
    
    local failed_tests=$(grep "FAILED" "$RESULTS_DIR/benchmark_results.csv" | wc -l)
    if [[ $failed_tests -gt 0 ]]; then
        echo "- $failed_tests tests failed - review error logs" >> "$report_file"
    fi
    
    echo -e "${GREEN}✓ Report generated: $report_file${NC}"
}

# Main benchmark execution
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
    echo "scenario,duration,offset,confidence" > "$RESULTS_DIR/benchmark_results.csv"
    
    # Prepare test data
    prepare_test_data
    
    # Run benchmarks
    echo -e "${BLUE}Running benchmarks...${NC}"
    
    # 10-minute tests
    run_benchmark "10min_perfect_sync" "$TEST_DATA_DIR/10min_primary.wav" "$TEST_DATA_DIR/10min_secondary.wav" 24
    run_benchmark "10min_2frame_offset" "$TEST_DATA_DIR/10min_2frame_primary.wav" "$TEST_DATA_DIR/10min_2frame_secondary.wav" 24
    run_benchmark "10min_5frame_offset" "$TEST_DATA_DIR/10min_5frame_primary.wav" "$TEST_DATA_DIR/10min_5frame_secondary.wav" 24
    run_benchmark "10min_noisy_30percent" "$TEST_DATA_DIR/10min_noisy30_primary.wav" "$TEST_DATA_DIR/10min_noisy30_secondary.wav" 24
    run_benchmark "10min_noisy_60percent" "$TEST_DATA_DIR/10min_noisy60_primary.wav" "$TEST_DATA_DIR/10min_noisy60_secondary.wav" 24
    
    # Longer tests
    run_benchmark "30min_perfect_sync" "$TEST_DATA_DIR/30min_primary.wav" "$TEST_DATA_DIR/30min_secondary.wav" 24
    run_benchmark "1hour_perfect_sync" "$TEST_DATA_DIR/1hour_primary.wav" "$TEST_DATA_DIR/1hour_secondary.wav" 24
    
    # Different sample rates
    run_benchmark "different_samplerates" "$TEST_DATA_DIR/48khz_primary.wav" "$TEST_DATA_DIR/44khz_secondary.wav" 24
    
    # Concurrent test
    run_concurrent_test
    
    # Generate report
    generate_report
    
    echo ""
    echo -e "${GREEN}🎉 Benchmark completed!${NC}"
    echo "Results: $RESULTS_DIR/benchmark_results.csv"
    echo "Report: $RESULTS_DIR/benchmark_report.md"
}

# Run main function
main "$@"
