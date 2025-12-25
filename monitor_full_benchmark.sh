#!/bin/bash
# Monitor full benchmark progress
# Refreshes every 30 seconds, shows progress, rate, and recent logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREEN_NAME="mini-azure-full-bench"
REFRESH_INTERVAL=30

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Trap Ctrl+C
trap 'echo ""; echo "Monitoring stopped."; exit 0' INT

while true; do
    clear
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Full Benchmark Monitor (500 tasks)${NC}"
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
    LATEST=$(ls -td "$SCRIPT_DIR/outputs/azure_gpt41mini_full_"* 2>/dev/null | head -1)
    
    if [ -n "$LATEST" ]; then
        echo -e "${BLUE}Latest Output:${NC}"
        echo "  Directory: $(basename "$LATEST")"
        echo ""
        
        # Check preds.json
        if [ -f "$LATEST/preds.json" ]; then
            COMPLETED=$(python3 -c "import json; print(len(json.load(open('$LATEST/preds.json'))))" 2>/dev/null || echo "0")
            REMAINING=$((500 - COMPLETED))
            PERCENT=$(echo "scale=1; $COMPLETED * 100 / 500" | bc 2>/dev/null || echo "0")
            
            echo -e "${GREEN}  Completed: $COMPLETED/500 instances (${PERCENT}%)${NC}"
            echo "  Remaining: $REMAINING instances"
            
            # Calculate rate if we have timing info
            if [ -f "$LATEST/status.log" ]; then
                START_TIME=$(grep "Starting benchmark" "$LATEST/status.log" 2>/dev/null | head -1 | sed 's/.*\[\(.*\)\].*/\1/')
                if [ -n "$START_TIME" ]; then
                    START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || echo "")
                    if [ -n "$START_EPOCH" ] && [ "$START_EPOCH" -gt 0 ] && [ "$COMPLETED" -gt 0 ]; then
                        NOW_EPOCH=$(date +%s)
                        ELAPSED=$((NOW_EPOCH - START_EPOCH))
                        if [ "$ELAPSED" -gt 0 ]; then
                            RATE=$(echo "scale=2; $COMPLETED * 3600 / $ELAPSED" | bc 2>/dev/null || echo "N/A")
                            ETA_SECONDS=$(echo "scale=0; $REMAINING * $ELAPSED / $COMPLETED" | bc 2>/dev/null || echo "N/A")
                            if [ "$ETA_SECONDS" != "N/A" ] && [ "$ETA_SECONDS" -gt 0 ]; then
                                ETA_HOURS=$(echo "scale=1; $ETA_SECONDS / 3600" | bc 2>/dev/null || echo "N/A")
                                echo "  Rate: ~${RATE} instances/hour"
                                echo "  ETA: ~${ETA_HOURS} hours"
                            fi
                        fi
                    fi
                fi
            fi
        else
            echo -e "${YELLOW}  preds.json not found yet - benchmark initializing...${NC}"
        fi
        
        # Show recent status log entries
        if [ -f "$LATEST/status.log" ]; then
            echo ""
            echo -e "${BLUE}Recent Status:${NC}"
            tail -5 "$LATEST/status.log" 2>/dev/null | sed 's/^/  /'
        fi
        
        # Show recent errors if any
        if [ -f "$LATEST/stderr.log" ]; then
            ERROR_COUNT=$(grep -i "error\|exception\|fail" "$LATEST/stderr.log" 2>/dev/null | wc -l)
            if [ "$ERROR_COUNT" -gt 0 ]; then
                echo ""
                echo -e "${YELLOW}  Recent errors: $ERROR_COUNT found (check stderr.log)${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ No output directories found yet${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Next refresh in ${REFRESH_INTERVAL} seconds..."
    echo "  Press Ctrl+C to stop monitoring"
    
    sleep "$REFRESH_INTERVAL"
done

