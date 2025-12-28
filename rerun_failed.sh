#!/bin/bash
# Re-run failed instances with fewer workers
# This will pick up from where we left off using existing preds.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/outputs/azure_gpt41mini_verified_20251224_221708"
WORKERS="${1:-64}"  # Default 64 workers (was 512)

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Re-running Failed Instances"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Output dir: $OUTPUT_DIR"
echo "  Workers: $WORKERS (reduced from 512)"
echo "  Remaining: $(python3 -c "import json; preds=json.load(open('$OUTPUT_DIR/preds.json')); print(500 - len(preds))") instances"
echo ""

# Load Azure credentials
PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "$PARENT_ENV" ]; then
    set -a
    source "$PARENT_ENV"
    set +a
fi

# Set Azure environment variables
export AZURE_API_KEY="$AZURE_OPENAI_APIKEY"
export AZURE_API_BASE="${AZURE_OPENAI_ENDPOINT%/openai/v1}"
export AZURE_API_VERSION="${AZURE_OPENAI_API_VERSION:-2025-01-01-preview}"
export MSWEA_SILENT_STARTUP=1

# Config file (already created)
CONFIG_FILE="$OUTPUT_DIR/config.yaml"

echo "Starting re-run at $(date)"
echo ""

# Run the benchmark (will skip existing entries in preds.json)
python -m minisweagent.run.extra.swebench \
    --subset verified \
    --split test \
    --workers "$WORKERS" \
    --config "$CONFIG_FILE" \
    --output "$OUTPUT_DIR"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Re-run completed at $(date)"
echo "  Final count: $(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "unknown") instances"
echo "═══════════════════════════════════════════════════════════════════════════"
