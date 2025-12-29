#!/bin/bash
# =============================================================================
# Run mini-swe-agent Benchmark with Ministral3-3B-SFT via vLLM
# Runs in screen session for safe disconnection
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WORKERS="${1:-8}"
SUBSET="${2:-verified}"
SLICE="${3:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/outputs/ministral3_${SUBSET}_${TIMESTAMP}"
SCREEN_NAME="ministral3_benchmark"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$OUTPUT_DIR/benchmark.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Ministral3-3B-SFT SWE-bench Benchmark (mini-swe-agent)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}[WARN] Screen session '$SCREEN_NAME' already exists${NC}"
    echo ""
    echo "Attach with: screen -r $SCREEN_NAME"
    echo "Kill with: screen -S $SCREEN_NAME -X quit"
    exit 1
fi

# Check vLLM server is running
VLLM_PORT=8000
if ! curl -s "http://localhost:$VLLM_PORT/v1/models" > /dev/null 2>&1; then
    echo -e "${RED}[ERROR] vLLM server not running on port $VLLM_PORT${NC}"
    echo ""
    echo "Please start vLLM server first:"
    echo "  ./start_vllm_ministral.sh"
    exit 1
fi

# Get served model name from vLLM
SERVED_MODEL=$(curl -s "http://localhost:$VLLM_PORT/v1/models" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "ministral3-3b-sft")
echo -e "${GREEN}✓ vLLM server is ready (model: $SERVED_MODEL)${NC}"
echo ""

# Ensure mini-swe-agent is installed
echo -e "${YELLOW}Checking mini-swe-agent installation...${NC}"
export MSWEA_SILENT_STARTUP=1
if ! python3 -c "import minisweagent" 2>/dev/null; then
    echo -e "${YELLOW}Installing mini-swe-agent...${NC}"
    cd "$SCRIPT_DIR"
    pip install -e . > /dev/null 2>&1
fi

# Ensure datasets and pyyaml are installed
if ! python3 -c "import datasets" 2>/dev/null; then
    echo -e "${YELLOW}Installing datasets...${NC}"
    pip install datasets > /dev/null 2>&1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    echo -e "${YELLOW}Installing pyyaml...${NC}"
    pip install pyyaml > /dev/null 2>&1
fi

echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create config file
CONFIG_FILE="$OUTPUT_DIR/config.yaml"
BASE_CONFIG="$SCRIPT_DIR/src/minisweagent/config/extra/swebench.yaml"

if [ ! -f "$BASE_CONFIG" ]; then
    echo -e "${RED}[ERROR] Base config not found: $BASE_CONFIG${NC}"
    exit 1
fi

# Copy base config and modify for local vLLM
cp "$BASE_CONFIG" "$CONFIG_FILE"

# Update model configuration for local vLLM
python3 << EOCONFIG
import yaml
from pathlib import Path

config_path = Path("$CONFIG_FILE")
with open(config_path) as f:
    config = yaml.safe_load(f)

# Update model config for local vLLM
config["model"] = {
    "model_class": "litellm",
    "model_name": "$SERVED_MODEL",
    "model_kwargs": {
        "custom_llm_provider": "openai",
        "api_base": "http://localhost:$VLLM_PORT/v1",
        "temperature": 0.0
    },
    "cost_tracking": "ignore_errors"
}

# Update environment to use docker cache if available
docker_cache = "/home/ubuntu/us-east-1-nano-chat-exp/docker-cache"
if Path(docker_cache).exists():
    config.setdefault("environment", {})
    config["environment"]["docker_cache_dir"] = docker_cache

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print(f"✓ Created config: {config_path}")
EOCONFIG

echo -e "${GREEN}Configuration:${NC}"
echo "  Model:        Ministral3-3B-SFT (via vLLM)"
echo "  Endpoint:     http://localhost:$VLLM_PORT/v1"
echo "  Framework:    mini-swe-agent"
echo "  Subset:       $SUBSET"
echo "  Workers:      $WORKERS"
if [ -n "$SLICE" ]; then
    echo "  Slice:        $SLICE (test mode)"
fi
echo "  Output:       $OUTPUT_DIR"
echo "  Screen:       $SCREEN_NAME"
echo "  Log File:     $LOG_FILE"
echo ""

# Create wrapper script for screen session
WRAPPER_SCRIPT="$LOG_DIR/run_benchmark_wrapper.sh"
cat > "$WRAPPER_SCRIPT" << EOFWRAP
#!/bin/bash
# Benchmark Wrapper (runs in screen session)

cd "$SCRIPT_DIR"

# Set environment variables
export OPENAI_API_KEY="EMPTY"
export OPENAI_API_BASE="http://localhost:$VLLM_PORT/v1"
export MSWEA_COST_TRACKING="ignore_errors"

# Use docker cache if available
DOCKER_CACHE="/home/ubuntu/us-east-1-nano-chat-exp/docker-cache"
if [ -d "\$DOCKER_CACHE" ]; then
    export HF_HOME="\$DOCKER_CACHE/huggingface"
    export DOCKER_CACHE_DIR="\$DOCKER_CACHE"
fi

echo "=============================================="
echo "  Ministral3-3B-SFT SWE-bench Benchmark"
echo "  Started: \$(date)"
echo "=============================================="
echo ""

# Build command
CMD="python -m minisweagent.run.extra.swebench \\
    --subset \"$SUBSET\" \\
    --split test \\
    --workers \"$WORKERS\" \\
    --config \"$CONFIG_FILE\" \\
    --output \"$OUTPUT_DIR\""

if [ -n "$SLICE" ]; then
    CMD="\$CMD --slice \"$SLICE\""
fi

# Run the benchmark
eval "\$CMD" 2>&1 | tee "$LOG_FILE"

EXITCODE=\${PIPESTATUS[0]}

echo ""
echo "=============================================="
if [ \$EXITCODE -eq 0 ]; then
    echo "✓ Benchmark completed successfully"
else
    echo "✗ Benchmark exited with code \$EXITCODE"
fi
echo "  End time:   \$(date)"
echo "  Output:     $OUTPUT_DIR"
echo "=============================================="

# Show results summary if preds.json exists
if [ -f "$OUTPUT_DIR/preds.json" ]; then
    COMPLETED=\$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
    echo "  Completed:  \$COMPLETED instances"
fi
EOFWRAP

chmod +x "$WRAPPER_SCRIPT"

# Launch in screen session
echo -e "${BLUE}Launching benchmark in screen session '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' started${NC}"
    echo ""
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $LOG_FILE"
    echo "  Monitor: ./monitor_ministral_benchmark.sh"
    echo ""
    echo -e "${GREEN}Safe to disconnect.${NC}"
else
    echo -e "${RED}Failed to start screen session${NC}"
    exit 1
fi

