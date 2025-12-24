#!/bin/bash
# Live progress monitor for mini-swe-agent Azure benchmark
# Refreshes every 30 seconds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREEN_NAME="mini-azure-gpt41mini-bench"
REFRESH_INTERVAL=30

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Trap Ctrl+C to exit cleanly
trap 'echo ""; echo "Monitoring stopped."; exit 0' INT

while true; do
    clear
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  mini-swe-agent Azure Benchmark Monitor${NC}"
    echo -e "${CYAN}  (Refreshing every ${REFRESH_INTERVAL}s - Press Ctrl+C to stop)${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Time: $(date)"
    echo ""
    
    # Check screen session
    if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
        echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' is running${NC}"
    else
        echo -e "${RED}✗ Screen session '$SCREEN_NAME' is not running${NC}"
    fi
    echo ""
    
    # Find latest output directory
    LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/azure_gpt41mini_"* 2>/dev/null | head -1)
    
    if [ -n "$LATEST_OUTPUT" ]; then
        echo -e "${BLUE}Latest Output:${NC}"
        echo "  Directory: $(basename "$LATEST_OUTPUT")"
        echo ""
        
        # Check preds.json
        if [ -f "$LATEST_OUTPUT/preds.json" ]; then
            COMPLETED=$(python3 -c "import json; print(len(json.load(open('$LATEST_OUTPUT/preds.json'))))" 2>/dev/null || echo "0")
            echo -e "${GREEN}  Completed: $COMPLETED instances${NC}"
            
            # Calculate rate if we have timing info
            if [ -f "$LATEST_OUTPUT/benchmark.log" ]; then
                # Try to extract start time from log
                START_TIME=$(grep "Start time:" "$LATEST_OUTPUT/benchmark.log" 2>/dev/null | head -1 | sed 's/.*Start time: //' || echo "")
                if [ -n "$START_TIME" ]; then
                    START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || echo "")
                    if [ -n "$START_EPOCH" ] && [ "$START_EPOCH" -gt 0 ]; then
                        NOW_EPOCH=$(date +%s)
                        ELAPSED=$((NOW_EPOCH - START_EPOCH))
                        if [ "$ELAPSED" -gt 0 ] && [ "$COMPLETED" -gt 0 ]; then
                            RATE=$(echo "scale=2; $COMPLETED * 3600 / $ELAPSED" | bc 2>/dev/null || echo "N/A")
                            echo "  Rate: ~${RATE} instances/hour"
                        fi
                    fi
                fi
            fi
        else
            echo -e "${YELLOW}  preds.json not found yet${NC}"
        fi
        
        # Show recent log entries
        if [ -f "$LATEST_OUTPUT/benchmark.log" ]; then
            echo ""
            echo -e "${BLUE}Recent Log Entries:${NC}"
            tail -5 "$LATEST_OUTPUT/benchmark.log" 2>/dev/null | sed 's/^/  /'
        fi
    else
        echo -e "${YELLOW}⚠ No output directories found${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Next refresh in ${REFRESH_INTERVAL} seconds..."
    echo "  Press Ctrl+C to stop monitoring"
    
    sleep "$REFRESH_INTERVAL"
done

