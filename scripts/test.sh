#!/bin/bash

# SLATE AI/ML Engine Test Script
# Usage: ./scripts/test.sh [type] [coverage]
# Type: unit|integration|performance|all (default: all)
# Coverage: true|false (default: true)

set -e

# Default values
TEST_TYPE=${1:-all}
COVERAGE=${2:-true}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_RESULTS_DIR="$PROJECT_ROOT/.test-results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running SLATE AI/ML Engine Tests${NC}"
echo "Test Type: $TEST_TYPE"
echo "Coverage: $COVERAGE"
echo ""

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"
mkdir -p "$TEST_RESULTS_DIR/coverage"

# Function to run unit tests
run_unit_tests() {
    echo -e "${YELLOW}Running unit tests...${NC}"
    
    local packages=("shared-types" "sync-engine" "ai-pipeline")
    local failed_tests=()
    
    for package in "${packages[@]}"; do
        echo -e "${BLUE}Testing $package...${NC}"
        
        cd "$PROJECT_ROOT/packages/$package"
        
        if [[ "$COVERAGE" == "true" ]]; then
            if ! swift test --enable-code-coverage; then
                failed_tests+=("$package")
            fi
        else
            if ! swift test; then
                failed_tests+=("$package")
            fi
        fi
        
        cd "$PROJECT_ROOT"
    done
    
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        echo -e "${RED}✗ Unit tests failed: ${failed_tests[*]}${NC}"
        return 1
    else
        echo -e "${GREEN}✓ All unit tests passed${NC}"
        return 0
    fi
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${YELLOW}Running integration tests...${NC}"
    
    cd "$PROJECT_ROOT"
    
    if [[ "$COVERAGE" == "true" ]]; then
        if swift test -c release --filter SLATEIntegrationTests --enable-code-coverage; then
            echo -e "${GREEN}✓ Integration tests passed${NC}"
            return 0
        fi
    else
        if swift test -c release --filter SLATEIntegrationTests; then
            echo -e "${GREEN}✓ Integration tests passed${NC}"
            return 0
        fi
    fi
    echo -e "${RED}✗ Integration tests failed${NC}"
    return 1
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${YELLOW}Running performance tests...${NC}"
    
    # Run sync benchmark
    echo -e "${BLUE}Running sync benchmark...${NC}"
    if "$PROJECT_ROOT/scripts/run-sync-benchmark.sh"; then
        echo -e "${GREEN}✓ Sync benchmark passed${NC}"
    else
        echo -e "${RED}✗ Sync benchmark failed${NC}"
        return 1
    fi
    
    # Run AI pipeline benchmark
    echo -e "${BLUE}Running AI pipeline benchmark...${NC}"
    if "$PROJECT_ROOT/scripts/run-ai-benchmark.sh"; then
        echo -e "${GREEN}✓ AI benchmark passed${NC}"
    else
        echo -e "${RED}✗ AI benchmark failed${NC}"
        return 1
    fi
    
    return 0
}

# Function to generate coverage report
generate_coverage_report() {
    if [[ "$COVERAGE" != "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Generating coverage report...${NC}"
    
    # Merge coverage data
    local coverage_files=("$TEST_RESULTS_DIR/coverage"/*.xcresult)
    local merged_file="$TEST_RESULTS_DIR/coverage/merged.xcresult"
    
    # Use xccov to merge coverage
    xccov merge --output "$merged_file" "${coverage_files[@]}" 2>/dev/null || true
    
    # Generate HTML report
    local html_dir="$TEST_RESULTS_DIR/coverage/html"
    mkdir -p "$html_dir"
    
    if command -v xccov &> /dev/null; then
        xccov view --report --json "$merged_file" > "$TEST_RESULTS_DIR/coverage/coverage.json" 2>/dev/null || true
        xccov view --report "$merged_file" | head -50 > "$TEST_RESULTS_DIR/coverage/coverage.txt" 2>/dev/null || true
        
        echo -e "${GREEN}✓ Coverage report generated${NC}"
        echo "JSON: $TEST_RESULTS_DIR/coverage/coverage.json"
        echo "Text: $TEST_RESULTS_DIR/coverage/coverage.txt"
    else
        echo -e "${YELLOW}⚠️ xccov not available, skipping detailed coverage report${NC}"
    fi
}

# Function to run linting
run_linting() {
    echo -e "${YELLOW}Running code analysis...${NC}"
    
    # SwiftFormat
    if command -v swiftformat &> /dev/null; then
        echo -e "${BLUE}Checking code formatting...${NC}"
        if swiftformat --lint "$PROJECT_ROOT"; then
            echo -e "${GREEN}✓ Code formatting is correct${NC}"
        else
            echo -e "${YELLOW}⚠️ Code formatting issues found${NC}"
        fi
    fi
    
    # SwiftLint
    if command -v swiftlint &> /dev/null; then
        echo -e "${BLUE}Running SwiftLint...${NC}"
        if swiftlint; then
            echo -e "${GREEN}✓ SwiftLint passed${NC}"
        else
            echo -e "${YELLOW}⚠️ SwiftLint warnings found${NC}"
        fi
    fi
}

# Function to validate test results
validate_results() {
    echo -e "${YELLOW}Validating test results...${NC}"
    echo -e "${GREEN}✓ Test run finished (see logs above for failures)${NC}"
    return 0
}

# Main test runner
main() {
    local test_failed=false
    
    # Run linting first
    run_linting
    
    # Run tests based on type
    case "$TEST_TYPE" in
        "unit")
            run_unit_tests || test_failed=true
            ;;
        "integration")
            run_integration_tests || test_failed=true
            ;;
        "performance")
            run_performance_tests || test_failed=true
            ;;
        "all")
            run_unit_tests || test_failed=true
            run_integration_tests || test_failed=true
            run_performance_tests || test_failed=true
            ;;
        *)
            echo -e "${RED}Unknown test type: $TEST_TYPE${NC}"
            exit 1
            ;;
    esac
    
    # Generate coverage report
    generate_coverage_report
    
    # Validate results
    validate_results || test_failed=true
    
    # Print summary
    echo ""
    if [[ "$test_failed" == true ]]; then
        echo -e "${RED}❌ Tests failed${NC}"
        echo "Check the test results in: $TEST_RESULTS_DIR"
        exit 1
    else
        echo -e "${GREEN}✅ All tests passed successfully!${NC}"
        echo "Test results available in: $TEST_RESULTS_DIR"
        
        if [[ "$COVERAGE" == "true" ]]; then
            echo "Coverage report: $TEST_RESULTS_DIR/coverage"
        fi
    fi
}

# Run main function
main "$@"
