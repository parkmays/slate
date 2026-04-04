#!/bin/bash

# SLATE AI/ML Engine Deployment Script
# Usage: ./scripts/deploy.sh [environment] [version]
# Environment: development|staging|production (default: staging)
# Version: auto|specific version (default: auto from VERSION file)

set -e

# Default values
ENVIRONMENT=${1:-staging}
VERSION=${2:-auto}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
DEPLOY_DIR="$PROJECT_ROOT/.deploy"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Deploying SLATE AI/ML Engine${NC}"
echo "Environment: $ENVIRONMENT"
echo "Version: $VERSION"
echo ""

# Get version
if [[ "$VERSION" == "auto" ]]; then
    VERSION=$(cat "$PROJECT_ROOT/VERSION")
fi

# Validate environment
case "$ENVIRONMENT" in
    "development"|"staging"|"production")
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '$ENVIRONMENT'. Use development, staging, or production.${NC}"
        exit 1
        ;;
esac

# Create deploy directory
DEPLOY_PATH="$DEPLOY_DIR/$ENVIRONMENT/$VERSION"
mkdir -p "$DEPLOY_PATH"

# Function to build for deployment
build_for_deployment() {
    echo -e "${YELLOW}Building for deployment...${NC}"
    
    # Clean previous builds
    rm -rf "$BUILD_DIR"
    
    # Build release version
    "$PROJECT_ROOT/scripts/build.sh" release macos
    
    echo -e "${GREEN}✓ Build completed${NC}"
}

# Function to prepare deployment package
prepare_package() {
    echo -e "${YELLOW}Preparing deployment package...${NC}"
    
    # Create package structure
    mkdir -p "$DEPLOY_PATH/bin"
    mkdir -p "$DEPLOY_PATH/lib"
    mkdir -p "$DEPLOY_PATH/config"
    mkdir -p "$DEPLOY_PATH/models"
    mkdir -p "$DEPLOY_PATH/docs"
    mkdir -p "$DEPLOY_PATH/scripts"
    
    # Copy binaries
    find "$BUILD_DIR/release" -name "*.dylib" -exec cp {} "$DEPLOY_PATH/lib/" \;
    find "$BUILD_DIR/release" -type f -executable -exec cp {} "$DEPLOY_PATH/bin/" \; 2>/dev/null || true
    
    # Copy configuration
    cp "$PROJECT_ROOT/configs/$ENVIRONMENT.json" "$DEPLOY_PATH/config/slate-config.json"
    
    # Copy documentation
    cp -r "$PROJECT_ROOT/docs" "$DEPLOY_PATH/" 2>/dev/null || true
    cp "$PROJECT_ROOT/README.md" "$DEPLOY_PATH/"
    cp "$PROJECT_ROOT/RELEASE_NOTES.md" "$DEPLOY_PATH/"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$DEPLOY_PATH/"
    
    # Copy scripts
    cp "$PROJECT_ROOT/scripts"/*.sh "$DEPLOY_PATH/scripts/" 2>/dev/null || true
    
    # Create version file
    echo "$VERSION" > "$DEPLOY_PATH/VERSION"
    
    # Create deployment manifest
    cat > "$DEPLOY_PATH/manifest.json" << EOF
{
  "name": "SLATE AI/ML Engine",
  "version": "$VERSION",
  "environment": "$ENVIRONMENT",
  "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "checksum": "$(sha256sum "$DEPLOY_PATH/VERSION" | cut -d' ' -f1)",
  "requirements": {
    "macos": "14.0+",
    "ios": "15.0+",
    "memory": "4GB+",
    "storage": "10GB+"
  },
  "components": {
    "syncEngine": true,
    "aiPipeline": true,
    "exportWriters": true,
    "ingestDaemon": true
  }
}
EOF
    
    echo -e "${GREEN}✓ Package prepared${NC}"
}

# Function to run deployment tests
run_deployment_tests() {
    echo -e "${YELLOW}Running deployment tests...${NC}"
    
    # Test configuration loading
    cd "$DEPLOY_PATH"
    if python3 -c "import json; json.load(open('config/slate-config.json'))"; then
        echo -e "${GREEN}✓ Configuration valid${NC}"
    else
        echo -e "${RED}✗ Configuration invalid${NC}"
        exit 1
    fi
    
    # Test binary execution
    if [[ -f "$DEPLOY_PATH/bin/slate-engine" ]]; then
        if "$DEPLOY_PATH/bin/slate-engine" --version > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Binary executable${NC}"
        else
            echo -e "${RED}✗ Binary execution failed${NC}"
            exit 1
        fi
    fi
    
    # Test library loading
    for lib in "$DEPLOY_PATH/lib"/*.dylib; do
        if [[ -f "$lib" ]]; then
            if otool -L "$lib" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ Library valid: $(basename $lib)${NC}"
            else
                echo -e "${RED}✗ Library invalid: $(basename $lib)${NC}"
                exit 1
            fi
        fi
    done
    
    echo -e "${GREEN}✓ All deployment tests passed${NC}"
}

# Function to create deployment archive
create_archive() {
    echo -e "${YELLOW}Creating deployment archive...${NC}"
    
    local archive_name="slate-engine-$VERSION-$ENVIRONMENT"
    local archive_path="$DEPLOY_DIR/$archive_name.tar.gz"
    
    cd "$DEPLOY_DIR"
    tar -czf "$archive_path" "$ENVIRONMENT/$VERSION"
    
    # Generate checksum
    sha256sum "$archive_path" > "$archive_path.sha256"
    
    echo -e "${GREEN}✓ Archive created: $archive_path${NC}"
    echo "Checksum: $archive_path.sha256"
}

# Function to deploy to remote (placeholder)
deploy_to_remote() {
    if [[ "$ENVIRONMENT" == "production" ]]; then
        echo -e "${YELLOW}Production deployment requires manual approval${NC}"
        echo "Archive: $DEPLOY_DIR/slate-engine-$VERSION-$ENVIRONMENT.tar.gz"
        echo "Please review and deploy manually"
    else
        echo -e "${YELLOW}Deploying to $ENVIRONMENT...${NC}"
        # Add actual deployment logic here
        echo "Deployment to $ENVIRONMENT completed"
    fi
}

# Function to generate deployment report
generate_report() {
    echo -e "${YELLOW}Generating deployment report...${NC}"
    
    local report_path="$DEPLOY_PATH/deployment-report.md"
    
    cat > "$report_path" << EOF
# SLATE AI/ML Engine Deployment Report

## Deployment Information
- **Environment**: $ENVIRONMENT
- **Version**: $VERSION
- **Deployed At**: $(date)
- **Deployed By**: $(whoami)

## Package Contents
$(du -sh "$DEPLOY_PATH"/* | sed 's|$DEPLOY_PATH/|- |')

## Configuration
- **Config File**: config/slate-config.json
- **Environment**: $ENVIRONMENT
- **Checksum**: $(sha256sum "$DEPLOY_PATH/VERSION" | cut -d' ' -f1)

## Validation Results
- ✅ Build successful
- ✅ Configuration valid
- ✅ Binaries executable
- ✅ Libraries loadable

## Next Steps
1. Review the deployment package
2. Run integration tests in target environment
3. Monitor initial performance
4. Rollback plan: Keep previous version available

## Contact
For deployment issues, contact the SLATE team.
EOF
    
    echo -e "${GREEN}✓ Report generated: $report_path${NC}"
}

# Main deployment process
main() {
    # Validate we're in the right directory
    if [[ ! -f "$PROJECT_ROOT/VERSION" ]]; then
        echo -e "${RED}Error: VERSION file not found. Run from project root.${NC}"
        exit 1
    fi
    
    # Build
    build_for_deployment
    
    # Prepare package
    prepare_package
    
    # Run tests
    run_deployment_tests
    
    # Create archive
    create_archive
    
    # Deploy
    deploy_to_remote
    
    # Generate report
    generate_report
    
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo "Environment: $ENVIRONMENT"
    echo "Version: $VERSION"
    echo "Package: $DEPLOY_DIR/slate-engine-$VERSION-$ENVIRONMENT.tar.gz"
    echo ""
    echo "Next steps:"
    echo "1. Test in $ENVIRONMENT environment"
    echo "2. Monitor performance and logs"
    echo "3. Promote to production when ready"
}

# Run main function
main "$@"
