#!/bin/bash
# Launch Azure OpenAI GPT-4.1-mini benchmark in a detached screen session
#
# Usage: ./run_azure_in_screen.sh [workers] [subset] [slice]
# Example: ./run_azure_in_screen.sh 512 verified
# Example: ./run_azure_in_screen.sh 64 verified "0:10"  # Test with first 10 tasks
#
# Screen session name: mini-azure-gpt41mini-bench
# To attach: screen -r mini-azure-gpt41mini-bench
# To detach: Ctrl+A, then D

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKERS="${1:-64}"
SUBSET="${2:-verified}"
SLICE="${3:-}"
SCREEN_NAME="mini-azure-gpt41mini-bench"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Azure OpenAI GPT-4.1-mini Benchmark Launcher (mini-swe-agent)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check for Azure credentials
PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "$PARENT_ENV" ]; then
    set -a
    source "$PARENT_ENV"
    set +a
fi

if [ -z "$AZURE_OPENAI_ENDPOINT" ] || [ -z "$AZURE_OPENAI_APIKEY" ]; then
    echo -e "${RED}ERROR: Azure OpenAI credentials not set${NC}"
    echo ""
    echo "Please ensure .env file has:"
    echo "  AZURE_OPENAI_ENDPOINT=..."
    echo "  AZURE_OPENAI_APIKEY=..."
    echo "  AZURE_DEPLOYMENT_NAME=..."
    echo ""
    exit 1
fi

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}Warning: Screen session '$SCREEN_NAME' already exists${NC}"
    echo ""
    echo "Options:"
    echo "  1. Attach to it:  screen -r $SCREEN_NAME"
    echo "  2. Kill it first: screen -S $SCREEN_NAME -X quit"
    echo ""
    read -p "Kill existing session and start new? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        screen -S "$SCREEN_NAME" -X quit
        sleep 1
    else
        echo "Exiting. Attach to existing session with: screen -r $SCREEN_NAME"
        exit 0
    fi
fi

# Create a wrapper script that will run in screen
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WRAPPER_SCRIPT="$SCRIPT_DIR/logs/run_azure_wrapper_${TIMESTAMP}.sh"
mkdir -p "$SCRIPT_DIR/logs"

cat > "$WRAPPER_SCRIPT" << EOFWRAPPER
#!/bin/bash
cd "$SCRIPT_DIR"

# Load Azure credentials from .env
PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "\$PARENT_ENV" ]; then
    set -a
    source "\$PARENT_ENV"
    set +a
fi

# Set Azure environment variables for litellm
export AZURE_API_KEY="\$AZURE_OPENAI_APIKEY"
export AZURE_API_BASE="\${AZURE_OPENAI_ENDPOINT%/openai/v1}"
export AZURE_API_VERSION="\${AZURE_OPENAI_API_VERSION:-2025-01-01-preview}"

# Run the benchmark
./run_azure_benchmark.sh $WORKERS $SUBSET $SLICE

# Keep screen alive after completion to view results
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
echo "Configuration:"
echo "  Model:    Azure OpenAI GPT-4.1-mini"
echo "  Framework: mini-swe-agent (baseline)"
echo "  Subset:   $SUBSET"
echo "  Workers:  $WORKERS (high parallelism for Azure high TPM quota)"
if [ -n "$SLICE" ]; then
    echo "  Slice:    $SLICE (test mode)"
fi
echo ""

screen -dmS "$SCREEN_NAME" bash "$WRAPPER_SCRIPT"

sleep 1

# Verify screen started
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session started successfully${NC}"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo "  Useful Commands:"
    echo ""
    echo "  Attach to session:     screen -r $SCREEN_NAME"
    echo "  Detach from session:   Ctrl+A, then D"
    echo "  View status:           ./status.sh"
    echo "  Monitor progress:      ./monitor.sh"
    echo "  Kill session:          screen -S $SCREEN_NAME -X quit"
    echo ""
    echo "  Latest output dir will be in: $SCRIPT_DIR/outputs/"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}✗ Failed to start screen session${NC}"
    exit 1
fi

