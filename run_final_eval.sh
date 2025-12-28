#!/bin/bash
# =============================================================================
# Run Final Evaluation on GPT-5-mini Results
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PREDS_FILE="$SCRIPT_DIR/outputs/gpt5mini_verified_20251225_055646/preds_final.json"
EVAL_DIR="$SCRIPT_DIR/logs/run_evaluation/gpt5mini-final-$TIMESTAMP"
SCREEN_NAME="gpt5mini_final"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Final GPT-5-mini Evaluation${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ ! -f "$PREDS_FILE" ]; then
    echo -e "${RED}Predictions file not found: $PREDS_FILE${NC}"
    exit 1
fi

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${RED}Screen '$SCREEN_NAME' already exists. Kill with: screen -S $SCREEN_NAME -X quit${NC}"
    exit 1
fi

mkdir -p "$EVAL_DIR"

# Convert to SWE-bench format
SWEBENCH_PREDS="$EVAL_DIR/preds_swebench.json"
echo "Converting to SWE-bench format..."
python3 << EOFCONV
import json
with open('$PREDS_FILE') as f:
    preds = json.load(f)

swebench_preds = {}
for iid, data in preds.items():
    patch = data.get('model_patch', '')
    swebench_preds[iid] = patch

with open('$SWEBENCH_PREDS', 'w') as f:
    json.dump(swebench_preds, f, indent=2)
print(f"  Converted {len(swebench_preds)} predictions")
EOFCONV
echo ""

# Create wrapper script
WRAPPER="$EVAL_DIR/run_eval.sh"
cat > "$WRAPPER" << EOFWRAP
#!/bin/bash
cd "$SCRIPT_DIR"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Final GPT-5-mini Evaluation"
echo "  Started: \$(date)"
echo "═══════════════════════════════════════════════════════════════════════════"

python -m swebench.harness.run_evaluation \\
    --predictions_path "$SWEBENCH_PREDS" \\
    --swe_bench_tasks princeton-nlp/SWE-bench_Verified \\
    --run_id "gpt5mini-final-$TIMESTAMP" \\
    --max_workers 16 \\
    --log_dir "$EVAL_DIR" \\
    2>&1 | tee "$EVAL_DIR/eval.log"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Generating Report..."
echo "═══════════════════════════════════════════════════════════════════════════"

# Generate final report
python3 << 'EOFREPORT'
import json
from pathlib import Path

eval_dir = Path('$EVAL_DIR')
report_file = list(eval_dir.glob('*.gpt5mini-final-*.json'))

if report_file:
    with open(report_file[0]) as f:
        results = json.load(f)
    
    resolved = len(results.get('resolved_ids', []))
    unresolved = len(results.get('unresolved_ids', []))
    errors = len(results.get('error_ids', []))
    
    print(f"\n{'='*60}")
    print("FINAL RESULTS")
    print('='*60)
    print(f"Resolved:   {resolved}")
    print(f"Unresolved: {unresolved}")
    print(f"Errors:     {errors}")
    print(f"Rate:       {resolved/500*100:.1f}%")
    print('='*60)
    
    # Save final summary
    summary = {
        "resolved": resolved,
        "unresolved": unresolved,
        "errors": errors,
        "resolve_rate": resolved/500*100
    }
    with open(eval_dir / 'final_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)
else:
    print("Report file not found")
EOFREPORT

echo "Completed: \$(date)"
echo "Press Enter to close..."
read
EOFWRAP
chmod +x "$WRAPPER"

echo -e "${BLUE}Launching evaluation in screen '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen '$SCREEN_NAME' started${NC}"
    echo ""
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $EVAL_DIR/eval.log"
    echo ""
    echo -e "${GREEN}Safe to disconnect.${NC}"
else
    echo -e "${RED}Failed to start screen${NC}"
    exit 1
fi

