#!/bin/bash
# =============================================================================
# Merge Fixed Patches and Run Evaluation
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_MERGED="/home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent/outputs/gpt5mini_verified_20251225_055646/preds_merged.json"
FIX_DIR=$(ls -td "$SCRIPT_DIR"/outputs/gpt5mini_fix_errors_* 2>/dev/null | head -1)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EVAL_DIR="$SCRIPT_DIR/logs/run_evaluation/gpt5mini-final-$TIMESTAMP"
SCREEN_NAME="gpt5mini_final_eval"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Merge Fixed Patches and Run Evaluation${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -z "$FIX_DIR" ]; then
    echo -e "${RED}No fix output directory found${NC}"
    exit 1
fi

FIX_PREDS="$FIX_DIR/preds.json"
if [ ! -f "$FIX_PREDS" ]; then
    echo -e "${RED}Fix predictions not found: $FIX_PREDS${NC}"
    exit 1
fi

# Check fix status
FIX_COUNT=$(python3 -c "import json; print(len(json.load(open('$FIX_PREDS'))))")
echo "Fixed instances: $FIX_COUNT"
echo ""

# Check patch quality
echo "Fixed patch quality:"
python3 << EOFPY
import json
with open('$FIX_PREDS') as f:
    preds = json.load(f)
for iid, data in preds.items():
    patch = data.get('model_patch', '')
    if patch.startswith('diff --git'):
        print(f"  ✓ {iid} ({len(patch)} chars, proper diff)")
    elif len(patch) > 100:
        print(f"  ? {iid} ({len(patch)} chars, unknown format)")
    else:
        print(f"  ✗ {iid} ({len(patch)} chars, likely bad)")
EOFPY
echo ""

# Merge predictions
MERGED_PREDS="$FIX_DIR/preds_final_merged.json"
echo "Merging predictions..."
python3 << EOFMERGE
import json

with open('$ORIGINAL_MERGED') as f:
    merged = json.load(f)

with open('$FIX_PREDS') as f:
    fixes = json.load(f)

# Replace bad patches with fixes
replaced = 0
for iid, data in fixes.items():
    patch = data.get('model_patch', '')
    if patch.startswith('diff --git') and len(patch) > 100:
        merged[iid] = data
        replaced += 1
        print(f"  Replaced: {iid}")

with open('$MERGED_PREDS', 'w') as f:
    json.dump(merged, f, indent=2)

print(f"\nMerged {replaced} fixed patches")
print(f"Total predictions: {len(merged)}")
EOFMERGE
echo ""

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${RED}Screen '$SCREEN_NAME' already exists${NC}"
    exit 1
fi

mkdir -p "$EVAL_DIR"

# Convert to SWE-bench format
SWEBENCH_PREDS="$EVAL_DIR/preds_swebench.json"
python3 << EOFCONV
import json
with open('$MERGED_PREDS') as f:
    preds = json.load(f)

swebench_preds = {}
for iid, data in preds.items():
    patch = data.get('model_patch', '')
    swebench_preds[iid] = patch

with open('$SWEBENCH_PREDS', 'w') as f:
    json.dump(swebench_preds, f, indent=2)
print(f"Converted {len(swebench_preds)} predictions to SWE-bench format")
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
echo "  Completed: \$(date)"
echo "═══════════════════════════════════════════════════════════════════════════"

# Generate report
python3 << 'EOFREPORT'
import json
import os
from pathlib import Path

eval_dir = Path('$EVAL_DIR')
report_file = eval_dir / 'gpt-5-mini.gpt5mini-final-$TIMESTAMP.json'

# Load results
results_file = eval_dir / 'gpt-5-mini' / 'gpt5mini-final-$TIMESTAMP.json'
if results_file.exists():
    with open(results_file) as f:
        results = json.load(f)
else:
    results = {}

resolved = set(results.get('resolved_ids', []))
unresolved = set(results.get('unresolved_ids', []))
error_ids = set(results.get('error_ids', []))

print(f"\n{'='*60}")
print("FINAL RESULTS")
print('='*60)
print(f"Resolved:   {len(resolved)}")
print(f"Unresolved: {len(unresolved)}")
print(f"Errors:     {len(error_ids)}")
print(f"Rate:       {len(resolved)/500*100:.1f}%")
print('='*60)
EOFREPORT

echo "Press Enter to close..."
read
EOFWRAP
chmod +x "$WRAPPER"

echo -e "${BLUE}Launching evaluation in screen...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen '$SCREEN_NAME' started${NC}"
    echo ""
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $EVAL_DIR/eval.log"
    echo ""
else
    echo -e "${RED}Failed to start screen${NC}"
    exit 1
fi

