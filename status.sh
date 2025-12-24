#!/bin/bash
# Quick status check for mini-swe-agent Azure benchmark

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREEN_NAME="mini-azure-gpt41mini-bench"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  mini-swe-agent Azure Benchmark Status${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check screen session
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' is running${NC}"
    echo "  Attach with: screen -r $SCREEN_NAME"
else
    echo -e "${YELLOW}⚠ Screen session '$SCREEN_NAME' is not running${NC}"
fi
echo ""

# Find latest output directory
LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/azure_gpt41mini_"* 2>/dev/null | head -1)

if [ -n "$LATEST_OUTPUT" ]; then
    echo -e "${BLUE}Latest Output:${NC}"
    echo "  Directory: $LATEST_OUTPUT"
    echo ""
    
    # Check preds.json
    if [ -f "$LATEST_OUTPUT/preds.json" ]; then
        COMPLETED=$(python3 -c "import json; print(len(json.load(open('$LATEST_OUTPUT/preds.json'))))" 2>/dev/null || echo "0")
        echo -e "${GREEN}  Completed: $COMPLETED instances${NC}"
    else
        echo -e "${YELLOW}  preds.json not found yet${NC}"
    fi
    
    # Check log file
    if [ -f "$LATEST_OUTPUT/benchmark.log" ]; then
        LOG_SIZE=$(du -h "$LATEST_OUTPUT/benchmark.log" | cut -f1)
        LAST_LINE=$(tail -1 "$LATEST_OUTPUT/benchmark.log" 2>/dev/null | head -c 100)
        echo "  Log size: $LOG_SIZE"
        if [ -n "$LAST_LINE" ]; then
            echo "  Last log: ${LAST_LINE}..."
        fi
    fi
else
    echo -e "${YELLOW}⚠ No output directories found${NC}"
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

