#!/bin/bash
# Monitor Error Fix Progress

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR=$(ls -td "$SCRIPT_DIR"/outputs/gpt5mini_fix_errors_* 2>/dev/null | head -1)

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GPT-5-mini Error Fix Monitor${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Screen status
if screen -list 2>/dev/null | grep -q "gpt5mini_fix"; then
    echo -e "${GREEN}● Screen: gpt5mini_fix (RUNNING)${NC}"
else
    echo -e "${YELLOW}○ Screen: gpt5mini_fix (NOT RUNNING)${NC}"
fi
echo ""

if [ -z "$OUTPUT_DIR" ]; then
    echo -e "${YELLOW}No output directory found yet${NC}"
    exit 0
fi

echo -e "${YELLOW}Output: $OUTPUT_DIR${NC}"
echo ""

# Progress
if [ -f "$OUTPUT_DIR/preds.json" ]; then
    COMPLETED=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo 0)
else
    COMPLETED=0
fi

echo "Progress: $COMPLETED/4 instances"
echo ""

# Check which instances done
echo "Instance Status:"
for inst in django__django-13794 psf__requests-1142 sphinx-doc__sphinx-9591 sphinx-doc__sphinx-8721; do
    if [ -f "$OUTPUT_DIR/preds.json" ] && python3 -c "import json; d=json.load(open('$OUTPUT_DIR/preds.json')); exit(0 if '$inst' in d else 1)" 2>/dev/null; then
        patch_len=$(python3 -c "import json; d=json.load(open('$OUTPUT_DIR/preds.json')); print(len(d.get('$inst',{}).get('model_patch','')))" 2>/dev/null || echo 0)
        if [ "$patch_len" -gt 100 ]; then
            echo -e "  ${GREEN}✓ $inst (patch: ${patch_len} chars)${NC}"
        else
            echo -e "  ${YELLOW}⚠ $inst (patch: ${patch_len} chars - might be bad)${NC}"
        fi
    else
        echo -e "  ${YELLOW}○ $inst (pending)${NC}"
    fi
done
echo ""

# Errors
if [ -f "$OUTPUT_DIR/benchmark.log" ]; then
    RATE_LIMIT=$(grep -c "RateLimitError" "$OUTPUT_DIR/benchmark.log" 2>/dev/null || echo 0)
    echo "Rate Limit Errors: $RATE_LIMIT"
fi
echo ""

echo -e "${BLUE}Commands:${NC}"
echo "  screen -r gpt5mini_fix"
echo "  tail -f $OUTPUT_DIR/benchmark.log"
echo ""

