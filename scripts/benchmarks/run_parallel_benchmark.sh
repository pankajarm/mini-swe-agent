#!/bin/bash
# Parallel Benchmark Runner for mini-swe-agent
# Resumes incomplete runs without interfering with existing benchmarks
#
# Usage: ./run_parallel_benchmark.sh [output_dir] [workers] [config]
# Example: ./run_parallel_benchmark.sh outputs/gpt5_mini_verified_500 12 config/extra/swebench_gpt5_mini.yaml

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
OUTPUT_DIR="${1:-outputs/gpt5_mini_verified_500}"
WORKERS="${2:-12}"
CONFIG="${3:-src/minisweagent/config/extra/swebench_gpt5_mini.yaml}"
SUBSET="${4:-verified}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Parallel Benchmark Runner${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Validate output directory
if [ ! -d "$OUTPUT_DIR" ]; then
    echo -e "${RED}ERROR: Output directory not found: $OUTPUT_DIR${NC}"
    exit 1
fi

# Check if preds.json exists (for resuming)
if [ -f "$OUTPUT_DIR/preds.json" ]; then
    COMPLETED=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
    echo -e "${YELLOW}Resuming existing run:${NC}"
    echo "  Output directory: $OUTPUT_DIR"
    echo "  Already completed: $COMPLETED tasks"
    echo "  Will skip completed tasks automatically"
else
    echo -e "${YELLOW}Starting new run:${NC}"
    echo "  Output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Check for API key
if [ -z "$OPENAI_API_KEY" ]; then
    # Try loading from parent .env
    PARENT_ENV="$(dirname "$SCRIPT_DIR")/.env"
    if [ -f "$PARENT_ENV" ]; then
        set -a
        source "$PARENT_ENV"
        set +a
    fi
fi

if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}ERROR: OPENAI_API_KEY not set${NC}"
    exit 1
fi

echo -e "${GREEN}✓ OPENAI_API_KEY is set${NC}"
echo ""

# Configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "  Model:       GPT-5-mini (from config)"
echo "  Subset:      $SUBSET"
echo "  Workers:     $WORKERS"
echo "  Output:      $OUTPUT_DIR"
echo "  Config:      $CONFIG"
echo ""

# Save config copy
if [ -f "$CONFIG" ]; then
    cp "$CONFIG" "$OUTPUT_DIR/config.yaml"
    echo -e "${GREEN}✓ Config saved to output directory${NC}"
fi

# Create screen session name based on output dir
SCREEN_NAME="bench-$(basename "$OUTPUT_DIR" | tr '/' '_' | tr '-' '_')"
# Limit screen name length
if [ ${#SCREEN_NAME} -gt 20 ]; then
    SCREEN_NAME="bench-$(echo "$(basename "$OUTPUT_DIR")" | md5sum | cut -c1-8)"
fi

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}Warning: Screen session '$SCREEN_NAME' already exists${NC}"
    echo "  Attach: screen -r $SCREEN_NAME"
    echo "  Kill:   screen -S $SCREEN_NAME -X quit"
    exit 1
fi

# Create wrapper script
WRAPPER_SCRIPT="/tmp/run_benchmark_${SCREEN_NAME}.sh"
cat > "$WRAPPER_SCRIPT" << EOFWRAPPER
#!/bin/bash
cd "$SCRIPT_DIR"

# Load API key
export OPENAI_API_KEY="$OPENAI_API_KEY"
export MSWEA_COST_TRACKING="ignore_errors"

# Run benchmark (will automatically skip completed tasks)
python -m minisweagent.run.extra.swebench \\
    --subset "$SUBSET" \\
    --split test \\
    --workers "$WORKERS" \\
    --config "$CONFIG" \\
    --output "$OUTPUT_DIR" \\
    2>&1 | tee "$OUTPUT_DIR/benchmark.log"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Benchmark complete. Press Enter to close this screen session..."
echo "═══════════════════════════════════════════════════════════════════════════"
read
EOFWRAPPER

chmod +x "$WRAPPER_SCRIPT"

# Launch screen session
echo -e "${GREEN}Launching benchmark in screen session: $SCREEN_NAME${NC}"
echo ""

screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"

sleep 2

# Verify screen started
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session started successfully${NC}"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo "  Useful Commands:"
    echo ""
    echo "  Attach to session:     screen -r $SCREEN_NAME"
    echo "  Detach from session:   Ctrl+A, then D"
    echo "  View logs:             tail -f $OUTPUT_DIR/benchmark.log"
    echo "  Kill session:          screen -S $SCREEN_NAME -X quit"
    echo ""
    echo "  Check status:          python3 -c \"import json; print(f'Completed: {len(json.load(open(\\\"$OUTPUT_DIR/preds.json\\\")))} tasks')\" 2>/dev/null || echo 'Starting...'"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}✗ Failed to start screen session${NC}"
    exit 1
fi

