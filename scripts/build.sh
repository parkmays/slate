#!/bin/bash

# SLATE AI/ML Engine Build Script
# Usage: ./scripts/build.sh [configuration] [platform]
# Configuration: debug|release (default: release)
# Platform: macos|ios|all (default: macos)

set -e

# Default values
CONFIGURATION=${1:-release}
PLATFORM=${2:-macos}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
ARCHIVE_DIR="$PROJECT_ROOT/.archives"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Building SLATE AI/ML Engine${NC}"
echo "Configuration: $CONFIGURATION"
echo "Platform: $PLATFORM"
echo ""

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR"

# Function to build a package
build_package() {
    local package_path=$1
    local package_name=$(basename "$package_path")
    
    echo -e "${YELLOW}Building $package_name...${NC}"
    
    cd "$package_path"
    
    if [[ "$PLATFORM" == "macos" ]] || [[ "$PLATFORM" == "all" ]]; then
        # Build for macOS
        swift build \
            -c "$CONFIGURATION" \
            --arch arm64 \
            --arch x86_64 \
            -Xswiftc -DSLATE_VERSION_STRING=\"$(cat "$PROJECT_ROOT/VERSION")\"
    fi
    
    if [[ "$PLATFORM" == "ios" ]] || [[ "$PLATFORM" == "all" ]]; then
        # Build for iOS
        swift build \
            -c "$CONFIGURATION" \
            -Xswiftc -target \
            -Xswiftc arm64-apple-ios15.0 \
            -Xswiftc -DSLATE_VERSION_STRING=\"$(cat "$PROJECT_ROOT/VERSION")\"
    fi
    
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ $package_name built successfully${NC}"
}

# Function to run tests
run_tests() {
    echo -e "${YELLOW}Running tests...${NC}"
    
    # Test sync engine
    cd "$PROJECT_ROOT/packages/sync-engine"
    swift test --enable-code-coverage
    
    # Test AI pipeline
    cd "$PROJECT_ROOT/packages/ai-pipeline"
    swift test --enable-code-coverage
    
    # Test shared types
    cd "$PROJECT_ROOT/packages/shared-types"
    swift test --enable-code-coverage
    
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓ All tests passed${NC}"
}

# Function to generate documentation
generate_docs() {
    echo -e "${YELLOW}Generating documentation...${NC}"
    
    # Create docs directory
    mkdir -p "$PROJECT_ROOT/docs/api"
    
    # Generate documentation for each package
    for package in "$PROJECT_ROOT"/packages/*/; do
        if [[ -d "$package" ]]; then
            package_name=$(basename "$package")
            echo "Generating docs for $package_name..."
            
            cd "$package"
            swift package \
                --allow-writing-to-directory "$PROJECT_ROOT/docs/api/$package_name" \
                generate-documentation \
                --target SLATE${package_name^} \
                --output-format html \
                --transform-for-static-hosting \
                --source-hosting-url https://github.com/slate-ai/slate-engine/tree/main \
                --source-hosting-git-reference main || true
            
            cd "$PROJECT_ROOT"
        fi
    done
    
    echo -e "${GREEN}✓ Documentation generated${NC}"
}

# Function to create release archive
create_archive() {
    echo -e "${YELLOW}Creating release archive...${NC}"
    
    local version=$(cat "$PROJECT_ROOT/VERSION")
    local archive_name="slate-engine-$version-$CONFIGURATION-$PLATFORM"
    local archive_path="$ARCHIVE_DIR/$archive_name.tar.gz"
    
    # Create temporary directory
    local temp_dir="$BUILD_DIR/$archive_name"
    mkdir -p "$temp_dir"
    
    # Copy built products
    find "$PROJECT_ROOT/.build" -name "*.build" -type d | while read dir; do
        cp -r "$dir" "$temp_dir/"
    done
    
    # Copy documentation
    if [[ -d "$PROJECT_ROOT/docs" ]]; then
        cp -r "$PROJECT_ROOT/docs" "$temp_dir/"
    fi
    
    # Copy configuration and examples
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        cp "$PROJECT_ROOT/README.md" "$temp_dir/"
    fi
    cp "$PROJECT_ROOT/RELEASE_NOTES.md" "$temp_dir/"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$temp_dir/"
    cp -r "$PROJECT_ROOT/examples" "$temp_dir/" 2>/dev/null || true
    
    # Create archive
    cd "$BUILD_DIR"
    tar -czf "$archive_path" "$archive_name"
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✓ Archive created: $archive_path${NC}"
}

# Function to validate build
validate_build() {
    echo -e "${YELLOW}Validating root Swift package (optional)...${NC}"
    cd "$PROJECT_ROOT"
    if swift build -c "$CONFIGURATION" 2>/dev/null; then
        echo -e "${GREEN}✓ Root package builds${NC}"
    else
        echo -e "${YELLOW}⚠ Root swift build skipped or failed — build individual packages under packages/ if needed.${NC}"
    fi
}

# Main build process
main() {
    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_ROOT/VERSION" ]]; then
        echo -e "${RED}Error: VERSION file not found. Run from project root.${NC}"
        exit 1
    fi
    
    # Clean previous builds
    echo -e "${YELLOW}Cleaning previous builds...${NC}"
    rm -rf "$BUILD_DIR"
    
    # Build all packages
    for package in "$PROJECT_ROOT"/packages/*/; do
        if [[ -d "$package/Sources" ]]; then
            build_package "$package"
        fi
    done
    
    # Run tests
    if [[ "$CONFIGURATION" == "debug" ]]; then
        run_tests
    fi
    
    # Generate documentation
    if [[ "$CONFIGURATION" == "release" ]]; then
        generate_docs
    fi
    
    # Validate build
    validate_build
    
    # Create archive for release builds
    if [[ "$CONFIGURATION" == "release" ]]; then
        create_archive
    fi
    
    echo ""
    echo -e "${GREEN}🎉 Build completed successfully!${NC}"
    echo "Configuration: $CONFIGURATION"
    echo "Platform: $PLATFORM"
    echo "Version: $(cat "$PROJECT_ROOT/VERSION")"
    
    if [[ "$CONFIGURATION" == "release" ]]; then
        echo "Archive: $ARCHIVE_DIR/slate-engine-$(cat $PROJECT_ROOT/VERSION)-$CONFIGURATION-$PLATFORM.tar.gz"
    fi
}

# Run main function
main "$@"
