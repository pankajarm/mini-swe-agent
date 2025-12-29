#!/bin/bash
# =============================================================================
# Run SWE-bench Verified Evaluation on Ministral3 Results
# Runs in screen session for safe disconnection
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PREDS_FILE="${1:-}"
EVAL_DIR="${2:-}"
SCREEN_NAME="ministral3_eval"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SWE-bench Verified Evaluation for Ministral3-3B-SFT${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Auto-detect predictions file if not provided
if [ -z "$PREDS_FILE" ]; then
    LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/ministral3_"* 2>/dev/null | head -1)
    if [ -n "$LATEST_OUTPUT" ] && [ -f "$LATEST_OUTPUT/preds.json" ]; then
        PREDS_FILE="$LATEST_OUTPUT/preds.json"
        echo -e "${YELLOW}Auto-detected predictions file: $PREDS_FILE${NC}"
    else
        echo -e "${RED}[ERROR] Predictions file not found${NC}"
        echo ""
        echo "Usage: $0 [preds_file] [eval_output_dir]"
        echo ""
        echo "Or place preds.json in the latest outputs/ministral3_* directory"
        exit 1
    fi
fi

if [ ! -f "$PREDS_FILE" ]; then
    echo -e "${RED}[ERROR] Predictions file not found: $PREDS_FILE${NC}"
    exit 1
fi

# Auto-detect eval directory if not provided
if [ -z "$EVAL_DIR" ]; then
    PREDS_DIR=$(dirname "$PREDS_FILE")
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    EVAL_DIR="$PREDS_DIR/evaluation_$TIMESTAMP"
fi

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}[WARN] Screen session '$SCREEN_NAME' already exists${NC}"
    echo ""
    echo "Attach with: screen -r $SCREEN_NAME"
    echo "Kill with: screen -S $SCREEN_NAME -X quit"
    exit 1
fi

mkdir -p "$EVAL_DIR"

echo -e "${GREEN}Configuration:${NC}"
echo "  Predictions:  $PREDS_FILE"
echo "  Output Dir:   $EVAL_DIR"
echo "  Screen:       $SCREEN_NAME"
echo ""

# Check predictions count
PRED_COUNT=$(python3 -c "import json; print(len(json.load(open('$PREDS_FILE'))))" 2>/dev/null || echo "0")
echo "  Predictions:  $PRED_COUNT instances"
echo ""

# Convert to SWE-bench format if needed
SWEBENCH_PREDS="$EVAL_DIR/preds_swebench.json"
echo "Converting to SWE-bench format..."
python3 << EOFCONV
import json
from pathlib import Path

preds_file = Path("$PREDS_FILE")
with open(preds_file) as f:
    preds = json.load(f)

# Convert from mini-swe-agent format (dict with instance_id keys) to SWE-bench format (dict instance_id -> patch)
swebench_preds = {}
for iid, data in preds.items():
    if isinstance(data, dict):
        patch = data.get("model_patch", data.get("patch", ""))
    else:
        # If data is already a string (patch), use it directly
        patch = str(data) if data else ""
    
    # Filter out invalid patches (e.g., error messages)
    if patch and not patch.startswith("Command '") and patch.strip():
        swebench_preds[iid] = patch

print(f"  Converted {len(swebench_preds)} predictions")

with open("$SWEBENCH_PREDS", 'w') as f:
    json.dump(swebench_preds, f, indent=2)

print(f"  Saved to: $SWEBENCH_PREDS")
EOFCONV
echo ""

# Create wrapper script for screen session
WRAPPER_SCRIPT="$EVAL_DIR/run_eval_wrapper.sh"
LOG_FILE="$EVAL_DIR/eval.log"

cat > "$WRAPPER_SCRIPT" << EOFWRAP
#!/bin/bash
# Evaluation Wrapper (runs in screen session)

cd "$SCRIPT_DIR"

echo "=============================================="
echo "  SWE-bench Verified Evaluation"
echo "  Started: \$(date)"
echo "=============================================="
echo ""
echo "  Predictions: $SWEBENCH_PREDS"
echo "  Count: $PRED_COUNT instances"
echo ""

# Use docker cache if available
DOCKER_CACHE="/home/ubuntu/us-east-1-nano-chat-exp/docker-cache"
if [ -d "\$DOCKER_CACHE" ]; then
    export DOCKER_CACHE_DIR="\$DOCKER_CACHE"
    export HF_HOME="\$DOCKER_CACHE/huggingface"
fi

# Run evaluation
python3 -m swebench.harness.run_evaluation \\
    --predictions_path "$SWEBENCH_PREDS" \\
    --swe_bench_tasks princeton-nlp/SWE-bench_Verified \\
    --run_id "ministral3-3b-sft-\$(date +%Y%m%d_%H%M%S)" \\
    --max_workers 16 \\
    --log_dir "$EVAL_DIR" \\
    2>&1 | tee "$LOG_FILE"

EXITCODE=\${PIPESTATUS[0]}

echo ""
echo "=============================================="
echo "  Generating Report..."
echo "=============================================="

# Generate final report
python3 << 'EOFREPORT'
import json
from pathlib import Path

eval_dir = Path("$EVAL_DIR")
log_dir = Path("$EVAL_DIR")

# Find result file (usually ends with .json)
result_files = list(log_dir.glob("*.json"))
if not result_files:
    # Try parent directory
    result_files = list(Path("$SCRIPT_DIR").glob("**/*ministral3*.json"))

if result_files:
    result_file = result_files[0]
    with open(result_file) as f:
        results = json.load(f)
    
    resolved = len(results.get('resolved_ids', []))
    unresolved = len(results.get('unresolved_ids', []))
    errors = len(results.get('error_ids', []))
    total = resolved + unresolved + errors
    
    print(f"\n{'='*60}")
    print("FINAL RESULTS")
    print('='*60)
    print(f"Resolved:   {resolved}")
    print(f"Unresolved: {unresolved}")
    print(f"Errors:     {errors}")
    print(f"Total:      {total}")
    if total > 0:
        print(f"Rate:       {resolved/total*100:.1f}%")
    print('='*60)
    
    # Save final summary
    summary = {
        "resolved": resolved,
        "unresolved": unresolved,
        "errors": errors,
        "total": total,
        "resolve_rate": resolved/total*100 if total > 0 else 0,
        "result_file": str(result_file)
    }
    with open(eval_dir / 'final_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\nSummary saved to: {eval_dir / 'final_summary.json'}")
else:
    print("⚠️  Result file not found - check logs")
EOFREPORT

echo ""
echo "=============================================="
if [ \$EXITCODE -eq 0 ]; then
    echo "✓ Evaluation completed successfully"
else
    echo "✗ Evaluation exited with code \$EXITCODE"
fi
echo "  End time:   \$(date)"
echo "  Output:     $EVAL_DIR"
echo "=============================================="
EOFWRAP

chmod +x "$WRAPPER_SCRIPT"

# Launch in screen session
echo -e "${BLUE}Launching evaluation in screen session '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' started${NC}"
    echo ""
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $LOG_FILE"
    echo ""
    echo -e "${GREEN}Safe to disconnect.${NC}"
else
    echo -e "${RED}Failed to start screen session${NC}"
    exit 1
fi

