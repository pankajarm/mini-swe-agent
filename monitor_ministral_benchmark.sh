#!/bin/bash
# =============================================================================
# Monitor Ministral3-3B-SFT Benchmark Progress
# Shows status of all screen sessions and processes
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REFRESH_INTERVAL="${1:-30}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Screen session names
VLLM_SCREEN="vllm_ministral3"
BENCH_SCREEN="ministral3_benchmark"
EVAL_SCREEN="ministral3_eval"
UPLOAD_SCREEN="ministral3_upload"

# Trap Ctrl+C to exit cleanly
trap 'echo ""; echo "Monitoring stopped."; exit 0' INT

print_status() {
    clear
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Ministral3-3B-SFT Benchmark Monitor${NC}"
    echo -e "${CYAN}  (Refreshing every ${REFRESH_INTERVAL}s - Press Ctrl+C to stop)${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Time: $(date)"
    echo ""
    
    # Check vLLM server
    echo -e "${BLUE}1. vLLM Server${NC}"
    if screen -list 2>/dev/null | grep -q "$VLLM_SCREEN"; then
        echo -e "   ${GREEN}✓ Screen session '$VLLM_SCREEN' is running${NC}"
        if curl -s "http://localhost:8000/v1/models" > /dev/null 2>&1; then
            MODEL=$(curl -s "http://localhost:8000/v1/models" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "unknown")
            echo -e "   ${GREEN}✓ Server is responding (model: $MODEL)${NC}"
        else
            echo -e "   ${YELLOW}⚠ Server not responding${NC}"
        fi
    else
        echo -e "   ${RED}✗ Screen session '$VLLM_SCREEN' is not running${NC}"
    fi
    
    # Check benchmark
    echo ""
    echo -e "${BLUE}2. Benchmark${NC}"
    if screen -list 2>/dev/null | grep -q "$BENCH_SCREEN"; then
        echo -e "   ${GREEN}✓ Screen session '$BENCH_SCREEN' is running${NC}"
        
        LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/ministral3_"* 2>/dev/null | head -1)
        if [ -n "$LATEST_OUTPUT" ]; then
            echo "   Output: $(basename "$LATEST_OUTPUT")"
            
            if [ -f "$LATEST_OUTPUT/preds.json" ]; then
                COMPLETED=$(python3 -c "import json; print(len(json.load(open('$LATEST_OUTPUT/preds.json'))))" 2>/dev/null || echo "0")
                echo -e "   ${GREEN}Completed: $COMPLETED instances${NC}"
                
                # Calculate rate if we have timing info
                if [ -f "$LATEST_OUTPUT/benchmark.log" ]; then
                    START_TIME=$(grep -i "start\|Started:" "$LATEST_OUTPUT/benchmark.log" 2>/dev/null | head -1 | sed 's/.*Started: //;s/.*Start time: //' || echo "")
                    if [ -n "$START_TIME" ]; then
                        START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || echo "")
                        if [ -n "$START_EPOCH" ] && [ "$START_EPOCH" -gt 0 ]; then
                            NOW_EPOCH=$(date +%s)
                            ELAPSED=$((NOW_EPOCH - START_EPOCH))
                            if [ "$ELAPSED" -gt 0 ] && [ "$COMPLETED" -gt 0 ]; then
                                RATE=$(echo "scale=2; $COMPLETED * 3600 / $ELAPSED" | bc 2>/dev/null || echo "N/A")
                                echo "   Rate: ~${RATE} instances/hour"
                            fi
                        fi
                    fi
                fi
            else
                echo -e "   ${YELLOW}⚠ preds.json not found yet${NC}"
            fi
            
            # Show recent log entries
            if [ -f "$LATEST_OUTPUT/benchmark.log" ]; then
                echo ""
                echo "   Recent log:"
                tail -3 "$LATEST_OUTPUT/benchmark.log" 2>/dev/null | sed 's/^/     /' | head -3
            fi
        fi
    else
        echo -e "   ${YELLOW}○ Screen session '$BENCH_SCREEN' is not running${NC}"
    fi
    
    # Check evaluation
    echo ""
    echo -e "${BLUE}3. Evaluation${NC}"
    if screen -list 2>/dev/null | grep -q "$EVAL_SCREEN"; then
        echo -e "   ${GREEN}✓ Screen session '$EVAL_SCREEN' is running${NC}"
        
        EVAL_DIR=$(find "$SCRIPT_DIR/outputs" -type d -name "evaluation_*" 2>/dev/null | sort -r | head -1)
        if [ -n "$EVAL_DIR" ] && [ -f "$EVAL_DIR/eval.log" ]; then
            echo "   Eval dir: $(basename "$EVAL_DIR")"
            if [ -f "$EVAL_DIR/final_summary.json" ]; then
                RESOLVED=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('resolved', 0))" 2>/dev/null || echo "0")
                TOTAL=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('total', 0))" 2>/dev/null || echo "0")
                echo -e "   ${GREEN}Resolved: $RESOLVED / $TOTAL${NC}"
            fi
        fi
    else
        echo -e "   ${YELLOW}○ Screen session '$EVAL_SCREEN' is not running${NC}"
    fi
    
    # Check upload
    echo ""
    echo -e "${BLUE}4. Upload${NC}"
    if screen -list 2>/dev/null | grep -q "$UPLOAD_SCREEN"; then
        echo -e "   ${GREEN}✓ Screen session '$UPLOAD_SCREEN' is running${NC}"
        
        LATEST_LOG=$(ls -t "$SCRIPT_DIR/logs/upload_ministral_"*.log 2>/dev/null | head -1)
        if [ -n "$LATEST_LOG" ]; then
            echo "   Log: $(basename "$LATEST_LOG")"
            tail -2 "$LATEST_LOG" 2>/dev/null | sed 's/^/     /' | head -2
        fi
    else
        echo -e "   ${YELLOW}○ Screen session '$UPLOAD_SCREEN' is not running${NC}"
    fi
    
    # GPU status
    echo ""
    echo -e "${BLUE}🖥️  GPU Status${NC}"
    if command -v nvidia-smi > /dev/null 2>&1; then
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader | sed 's/^/   /'
    else
        echo "   nvidia-smi not available"
    fi
    
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Next refresh in ${REFRESH_INTERVAL} seconds..."
    echo "  Press Ctrl+C to stop monitoring"
    echo ""
    echo "  Quick commands:"
    echo "    screen -r $VLLM_SCREEN    # Attach to vLLM"
    echo "    screen -r $BENCH_SCREEN   # Attach to benchmark"
    echo "    screen -r $EVAL_SCREEN    # Attach to evaluation"
    echo "    screen -r $UPLOAD_SCREEN  # Attach to upload"
}

# Main loop
case "${1}" in
    --once|-o)
        print_status
        ;;
    *)
        while true; do
            print_status
            sleep "$REFRESH_INTERVAL"
        done
        ;;
esac

