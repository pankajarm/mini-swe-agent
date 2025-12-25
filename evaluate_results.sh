#!/bin/bash
# Evaluate mini-swe-agent benchmark results
# Usage: ./evaluate_results.sh [output_dir] [workers]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$(ls -td "$SCRIPT_DIR/outputs/azure_gpt41mini_full_"* 2>/dev/null | head -1)}"
WORKERS="${2:-32}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$OUTPUT_DIR" ] || [ ! -d "$OUTPUT_DIR" ]; then
    echo -e "${RED}ERROR: Output directory not found${NC}"
    echo "Usage: $0 [output_dir] [workers]"
    exit 1
fi

PREDS_FILE="$OUTPUT_DIR/preds.json"

if [ ! -f "$PREDS_FILE" ]; then
    echo -e "${RED}ERROR: preds.json not found in $OUTPUT_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Evaluating mini-swe-agent Results${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Predictions file: $PREDS_FILE"
echo "Workers: $WORKERS"
echo ""

# Count predictions
PREDS_COUNT=$(python3 -c "import json; print(len(json.load(open('$PREDS_FILE'))))" 2>/dev/null || echo "0")
echo -e "${GREEN}✓ Found $PREDS_COUNT predictions${NC}"
echo ""

# Check if swebench is installed
if ! python -c "import swebench" 2>/dev/null; then
    echo -e "${YELLOW}Installing swebench...${NC}"
    pip install swebench
fi

# Use the evaluation script from swe-bench-huggingface-models if available
EVAL_SCRIPT="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/scripts/evaluate.py"
if [ -f "$EVAL_SCRIPT" ]; then
    echo -e "${BLUE}Running evaluation using standard script...${NC}"
    python "$EVAL_SCRIPT" "$PREDS_FILE" --workers "$WORKERS"
else
    echo -e "${YELLOW}Standard eval script not found, using swebench directly...${NC}"
    python -m swebench.harness.run_evaluation \
        --dataset_name "princeton-nlp/SWE-bench_Verified" \
        --predictions_path "$PREDS_FILE" \
        --max_workers "$WORKERS" \
        --run_id "mini-swe-agent-azure-$(date +%Y%m%d_%H%M%S)"
fi

# Find evaluation results
EVAL_DIR="evaluation_results"
if [ -d "$EVAL_DIR" ]; then
    LATEST_EVAL=$(ls -td "$EVAL_DIR"/* 2>/dev/null | head -1)
    if [ -n "$LATEST_EVAL" ]; then
        echo ""
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Evaluation Results Summary${NC}"
        echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
        
        # Look for results JSON file
        RESULTS_FILE=$(find "$LATEST_EVAL" -name "*.json" -type f | grep -E "(results|eval)" | head -1)
        if [ -n "$RESULTS_FILE" ] && [ -f "$RESULTS_FILE" ]; then
            python3 << PYEOF
import json
import sys

try:
    with open("$RESULTS_FILE") as f:
        data = json.load(f)
    
    total = data.get('total_instances', 500)
    submitted = data.get('submitted_instances', 0)
    resolved = data.get('resolved_instances', 0)
    unresolved = data.get('unresolved_instances', 0)
    errors = data.get('error_instances', 0)
    
    rate = (resolved / total * 100) if total > 0 else 0
    submit_rate = (submitted / total * 100) if total > 0 else 0
    
    print(f"Total instances:     {total}")
    print(f"Submitted:           {submitted} ({submit_rate:.1f}%)")
    print(f"Resolved (passed):   {resolved} ({rate:.1f}%)")
    print(f"Unresolved (failed): {unresolved}")
    print(f"Errors:              {errors}")
    print(f"")
    print(f"🎯 RESOLVE RATE: {resolved}/{total} = {rate:.1f}%")
    print(f"📤 SUBMIT RATE: {submitted}/{total} = {submit_rate:.1f}%")
    
except Exception as e:
    print(f"Error reading results: {e}", file=sys.stderr)
PYEOF
        fi
    fi
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

