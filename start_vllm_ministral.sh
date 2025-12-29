#!/bin/bash
# =============================================================================
# Start vLLM Server for Ministral3-3B-SFT Model
# Runs in screen session for safe disconnection
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Use local patched model (ministral3 -> ministral for transformers compatibility)
MODEL_ID="$SCRIPT_DIR/models/ministral3-3b-sft"
SERVED_NAME="ministral3-3b-sft"
VLLM_PORT=8000
SCREEN_NAME="vllm_ministral3"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/vllm_ministral3.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Starting vLLM Server for Ministral3-3B-SFT${NC}"
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

# Check if vLLM is already running on the port
if curl -s "http://localhost:$VLLM_PORT/v1/models" > /dev/null 2>&1; then
    echo -e "${YELLOW}[WARN] vLLM server already running on port $VLLM_PORT${NC}"
    echo ""
    echo "Current vLLM process:"
    ps aux | grep "vllm.entrypoints" | grep -v grep | head -1
    echo ""
    read -p "Stop existing server and start new one? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping existing vLLM server..."
        pkill -f "vllm.entrypoints.openai.api_server" || true
        sleep 5
    else
        echo "Exiting..."
        exit 0
    fi
fi

# Detect number of GPUs
NUM_GPUS=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
if [ "$NUM_GPUS" -eq 0 ]; then
    echo -e "${RED}[ERROR] No GPUs detected${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Model:        $MODEL_ID"
echo "  Served Name:  $SERVED_NAME"
echo "  Port:         $VLLM_PORT"
echo "  GPUs:         $NUM_GPUS"
echo "  Screen:       $SCREEN_NAME"
echo "  Log File:     $LOG_FILE"
echo ""

# Use the venv with vLLM + transformers 5.0.0.dev0 (ministral3 support)
VLLM_VENV="$SCRIPT_DIR/.venv-vllm"
if [ -d "$VLLM_VENV" ]; then
    echo -e "${GREEN}✓ Using vLLM venv with ministral3 support${NC}"
else
    echo -e "${RED}[ERROR] vLLM venv not found at $VLLM_VENV${NC}"
    echo "Run: cd $SCRIPT_DIR && uv venv .venv-vllm && source .venv-vllm/bin/activate && uv pip install vllm 'transformers @ git+https://github.com/huggingface/transformers.git@main'"
    exit 1
fi

# Create wrapper script for screen session
WRAPPER_SCRIPT="$LOG_DIR/start_vllm_wrapper.sh"
cat > "$WRAPPER_SCRIPT" << EOFWRAP
#!/bin/bash
# vLLM Server Wrapper (runs in screen session)

cd "$SCRIPT_DIR"

# Activate virtual environment if found
if [ -n "$VLLM_VENV" ]; then
    source "$VLLM_VENV/bin/activate"
elif [ -d "$SCRIPT_DIR/.venv" ]; then
    source "$SCRIPT_DIR/.venv/bin/activate"
fi

# Set cache directories
export HF_HOME="\${HF_HOME:-$HOME/.cache/huggingface}"
export PIP_CACHE_DIR="\${PIP_CACHE_DIR:-$HOME/.cache/pip}"

# Use docker cache if available
DOCKER_CACHE="/home/ubuntu/us-east-1-nano-chat-exp/docker-cache"
if [ -d "\$DOCKER_CACHE" ]; then
    export HF_HOME="\$DOCKER_CACHE/huggingface"
fi

# Set HuggingFace token
export HF_TOKEN="${HF_TOKEN:-}"
export HUGGINGFACE_HUB_TOKEN="${HUGGINGFACE_HUB_TOKEN:-${HF_TOKEN:-}}"

echo "Starting vLLM server..."
echo "Model: $MODEL_ID"
echo "Started: \$(date)"
echo "Python: \$(which python)"
echo "vLLM: \$(python -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo 'not found')"
if [ -n "\${HF_TOKEN:-}" ]; then
    echo "HF Token: ***\${HF_TOKEN: -4} (present)"
else
    echo "HF Token: (not set)"
fi
echo ""
echo "=============================================="

# Start vLLM server
python -m vllm.entrypoints.openai.api_server \\
    --model "$MODEL_ID" \\
    --served-model-name "$SERVED_NAME" \\
    --host 0.0.0.0 \\
    --port $VLLM_PORT \\
    --tensor-parallel-size $NUM_GPUS \\
    --gpu-memory-utilization 0.95 \\
    --max-num-seqs 256 \\
    --max-model-len 32768 \\
    --trust-remote-code \\
    2>&1 | tee "$LOG_FILE"

echo ""
echo "vLLM server stopped at: \$(date)"
EOFWRAP

chmod +x "$WRAPPER_SCRIPT"

# Launch in screen session
echo -e "${BLUE}Launching vLLM server in screen session '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"
sleep 3

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' started${NC}"
    echo ""
    echo "Waiting for vLLM server to be ready..."
    
    # Wait for server to be ready (max 5 minutes)
    for i in {1..60}; do
        if curl -s "http://localhost:$VLLM_PORT/v1/models" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('Model:', d['data'][0]['id'])" 2>/dev/null; then
            echo ""
            echo -e "${GREEN}✓ vLLM server is ready${NC}"
            echo ""
            echo "  Model endpoint: http://localhost:$VLLM_PORT/v1"
            echo "  Screen session: screen -r $SCREEN_NAME"
            echo "  Log file:       $LOG_FILE"
            echo "  Monitor:        tail -f $LOG_FILE"
            echo ""
            echo -e "${GREEN}Safe to disconnect.${NC}"
            exit 0
        fi
        echo -n "."
        sleep 5
    done
    
    echo ""
    echo -e "${YELLOW}[WARN] Server not ready after 5 minutes. Check logs:${NC}"
    echo "  tail -f $LOG_FILE"
    echo "  screen -r $SCREEN_NAME"
else
    echo -e "${RED}Failed to start screen session${NC}"
    exit 1
fi

