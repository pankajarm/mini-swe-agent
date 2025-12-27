#!/bin/bash
# Monitor Final Evaluation Progress

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_DIR=$(ls -td "$SCRIPT_DIR"/logs/run_evaluation/gpt5mini-final-* 2>/dev/null | head -1)

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GPT-5-mini Final Evaluation Monitor${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Screen status
if screen -list 2>/dev/null | grep -q "gpt5mini_final"; then
    echo -e "${GREEN}● Screen: gpt5mini_final (RUNNING)${NC}"
else
    echo -e "${YELLOW}○ Screen: gpt5mini_final (NOT RUNNING)${NC}"
fi
echo ""

if [ -z "$EVAL_DIR" ]; then
    echo -e "${YELLOW}No evaluation directory found${NC}"
    exit 0
fi

echo "Directory: $EVAL_DIR"
echo ""

# Check for report file
REPORT_FILE=$(ls "$EVAL_DIR"/*.gpt5mini-final-*.json 2>/dev/null | head -1)

if [ -n "$REPORT_FILE" ]; then
    echo -e "${GREEN}✓ Evaluation complete!${NC}"
    python3 << EOFPY
import json
with open('$REPORT_FILE') as f:
    r = json.load(f)
resolved = len(r.get('resolved_ids', []))
unresolved = len(r.get('unresolved_ids', []))
errors = len(r.get('error_ids', []))
print(f"\nResults:")
print(f"  Resolved:   {resolved} ({resolved/500*100:.1f}%)")
print(f"  Unresolved: {unresolved}")
print(f"  Errors:     {errors}")
EOFPY
else
    # Count progress from instance logs
    if [ -d "$EVAL_DIR/gpt-5-mini" ]; then
        INSTANCE_LOGS=$(find "$EVAL_DIR/gpt-5-mini" -name "report.json" 2>/dev/null | wc -l)
        echo "Evaluated: $INSTANCE_LOGS/500 instances"
    fi
    
    # Show last log lines
    if [ -f "$EVAL_DIR/eval.log" ]; then
        echo ""
        echo "Last log lines:"
        tail -5 "$EVAL_DIR/eval.log" 2>/dev/null | sed 's/^/  /'
    fi
fi
echo ""

echo -e "${BLUE}Commands:${NC}"
echo "  screen -r gpt5mini_final"
echo "  tail -f $EVAL_DIR/eval.log"
echo ""

