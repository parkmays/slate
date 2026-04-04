#!/usr/bin/env bash
# SLATE — Validate all contract files in contracts/
# Ensures all present contract files are valid JSON before any agent proceeds.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONTRACTS_DIR="$(dirname "$0")/../contracts"
REQUIRED_CONTRACT="data-model.json"
OPTIONAL_CONTRACTS=("sync-api.json" "ai-scores-api.json" "web-api.json" "realtime-events.json")
ERRORS=0

echo "Validating contracts in $CONTRACTS_DIR..."
echo ""

# Required: data-model.json must always exist
REQUIRED_PATH="$CONTRACTS_DIR/$REQUIRED_CONTRACT"
if [ ! -f "$REQUIRED_PATH" ]; then
  echo -e "${RED}✗${NC} MISSING (required): $REQUIRED_CONTRACT"
  echo "  Claude Code must publish this before any other agent starts."
  ERRORS=$((ERRORS + 1))
else
  if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$REQUIRED_PATH" 2>/dev/null; then
    VERSION=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('version','?'))" "$REQUIRED_PATH")
    AUTHOR=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('author','?'))" "$REQUIRED_PATH")
    echo -e "${GREEN}✓${NC} $REQUIRED_CONTRACT  (version=$VERSION, author=$AUTHOR)"
  else
    echo -e "${RED}✗${NC} INVALID JSON: $REQUIRED_CONTRACT"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Optional: validate if present, warn if absent
for CONTRACT in "${OPTIONAL_CONTRACTS[@]}"; do
  CONTRACT_PATH="$CONTRACTS_DIR/$CONTRACT"
  if [ -f "$CONTRACT_PATH" ]; then
    if python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$CONTRACT_PATH" 2>/dev/null; then
      VERSION=$(python3 -c "import json, sys; d=json.load(open(sys.argv[1])); print(d.get('version','?'))" "$CONTRACT_PATH" 2>/dev/null || echo "?")
      echo -e "${GREEN}✓${NC} $CONTRACT  (version=$VERSION)"
    else
      echo -e "${RED}✗${NC} INVALID JSON: $CONTRACT"
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo -e "${YELLOW}⚠${NC} PENDING: $CONTRACT  (not yet published)"
  fi
done

echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All contracts valid.${NC}"
else
  echo -e "${RED}$ERRORS contract error(s) found. Fix before proceeding.${NC}"
  exit 1
fi
