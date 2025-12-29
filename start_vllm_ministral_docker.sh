#!/bin/bash
# =============================================================================
# Start vLLM Server for Ministral3-3B-SFT Model using Docker
# Alternative approach if direct vLLM has compatibility issues
# Runs in screen session for safe disconnection
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODEL_ID="pankajmathur/ministral3-3b-sft-openthoughts-merged"
VLLM_PORT=8000
SCREEN_NAME="vllm_ministral3_docker"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/vllm_ministral3_docker.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$LOG_DIR"

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Starting vLLM Server (Docker) for Ministral3-3B-SFT${NC}"
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

# Check if Docker container is already running
if docker ps | grep -q "vllm-ministral3"; then
    echo -e "${YELLOW}[WARN] Docker container 'vllm-ministral3' already running${NC}"
    echo ""
    docker ps | grep "vllm-ministral3"
    exit 1
fi

# Get HuggingFace token
HF_TOKEN=""
if [ -f "/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env" ]; then
    # Source .env file safely, ignoring errors from malformed lines
    set -a
    source /home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env 2>/dev/null || true
    set +a
fi

# Also check for token in environment or try to extract from .env directly
HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_TOKEN:-${HUGGINGFACE_WRITE_TOKEN:-}}}"

# If still not found, try to grep it from .env file
if [ -z "$HF_TOKEN" ] && [ -f "/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env" ]; then
    HF_TOKEN=$(grep -E "^HUGGINGFACE_WRITE_TOKEN=|^HF_TOKEN=|^HUGGINGFACE_TOKEN=" /home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"' || echo "")
fi

if [ -z "$HF_TOKEN" ]; then
    echo -e "${RED}[ERROR] HuggingFace token not found${NC}"
    echo "Please set HF_TOKEN, HUGGINGFACE_TOKEN, or HUGGINGFACE_WRITE_TOKEN"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Model:        $MODEL_ID"
echo "  Port:         $VLLM_PORT"
echo "  Screen:       $SCREEN_NAME"
echo "  Log File:     $LOG_FILE"
echo ""

# Create wrapper script for screen session
WRAPPER_SCRIPT="$LOG_DIR/start_vllm_docker_wrapper.sh"
cat > "$WRAPPER_SCRIPT" << EOFWRAP
#!/bin/bash
# vLLM Docker Wrapper (runs in screen session)

cd "$SCRIPT_DIR"

echo "Starting vLLM server in Docker..."
echo "Model: $MODEL_ID"
echo "Started: \$(date)"
echo ""
echo "=============================================="

# Stop existing container if any
docker stop vllm-ministral3 2>/dev/null || true
docker rm vllm-ministral3 2>/dev/null || true

# Start vLLM server in Docker
docker run -d \\
    --name vllm-ministral3 \\
    --gpus all \\
    -p $VLLM_PORT:8000 \\
    -e HF_TOKEN="$HF_TOKEN" \\
    -e HUGGINGFACE_HUB_TOKEN="$HF_TOKEN" \\
    --ipc=host \\
    vllm/vllm-openai:latest \\
    --model "$MODEL_ID" \\
    --host 0.0.0.0 \\
    --port 8000 \\
    2>&1 | tee "$LOG_FILE"

CONTAINER_ID=\$(docker ps -q -f name=vllm-ministral3)
echo "Container started: \$CONTAINER_ID"
echo ""

# Follow logs
docker logs -f vllm-ministral3 2>&1 | tee -a "$LOG_FILE"
EOFWRAP

chmod +x "$WRAPPER_SCRIPT"

# Launch in screen session
echo -e "${BLUE}Launching vLLM Docker container in screen session '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"
sleep 3

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' started${NC}"
    echo ""
    echo "Waiting for vLLM server to be ready..."
    
    # Wait for server to be ready (max 5 minutes)
    for i in {1..60}; do
        if curl -s "http://localhost:$VLLM_PORT/v1/models" > /dev/null 2>&1; then
            echo ""
            echo -e "${GREEN}✓ vLLM server is ready${NC}"
            echo ""
            echo "  Model endpoint: http://localhost:$VLLM_PORT/v1"
            echo "  Screen session: screen -r $SCREEN_NAME"
            echo "  Log file:       $LOG_FILE"
            echo "  Container:      docker logs -f vllm-ministral3"
            echo ""
            echo -e "${GREEN}Safe to disconnect.${NC}"
            exit 0
        fi
        echo -n "."
        sleep 5
    done
    
    echo ""
    echo -e "${YELLOW}[WARN] Server not ready after 5 minutes. Check logs:${NC}"
    echo "  docker logs vllm-ministral3"
    echo "  screen -r $SCREEN_NAME"
else
    echo -e "${RED}Failed to start screen session${NC}"
    exit 1
fi

