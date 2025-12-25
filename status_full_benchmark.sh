#!/bin/bash
# Quick status check for full benchmark

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREEN_NAME="mini-azure-full-bench"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Full Benchmark Status${NC}"
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
LATEST=$(ls -td "$SCRIPT_DIR/outputs/azure_gpt41mini_full_"* 2>/dev/null | head -1)

if [ -n "$LATEST" ]; then
    echo -e "${BLUE}Latest Output:${NC}"
    echo "  Directory: $LATEST"
    echo ""
    
    # Check preds.json
    if [ -f "$LATEST/preds.json" ]; then
        COMPLETED=$(python3 -c "import json; print(len(json.load(open('$LATEST/preds.json'))))" 2>/dev/null || echo "0")
        REMAINING=$((500 - COMPLETED))
        PERCENT=$(echo "scale=1; $COMPLETED * 100 / 500" | bc 2>/dev/null || echo "0")
        echo -e "${GREEN}  Completed: $COMPLETED/500 instances (${PERCENT}%)${NC}"
        echo "  Remaining: $REMAINING instances"
    else
        echo -e "${YELLOW}  preds.json not found yet${NC}"
    fi
    
    # Check log files
    if [ -f "$LATEST/benchmark.log" ]; then
        LOG_SIZE=$(du -h "$LATEST/benchmark.log" | cut -f1)
        echo "  Main log size: $LOG_SIZE"
    fi
    
    if [ -f "$LATEST/status.log" ]; then
        echo ""
        echo -e "${BLUE}Latest Status:${NC}"
        tail -3 "$LATEST/status.log" 2>/dev/null | sed 's/^/  /'
    fi
    
    # Check for errors
    if [ -f "$LATEST/stderr.log" ]; then
        ERROR_COUNT=$(grep -i "error\|exception\|fail" "$LATEST/stderr.log" 2>/dev/null | wc -l)
        if [ "$ERROR_COUNT" -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}  ⚠ Errors found: $ERROR_COUNT (check stderr.log)${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ No output directories found${NC}"
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

