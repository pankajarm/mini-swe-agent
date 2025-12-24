#!/bin/bash
# Azure OpenAI GPT-4.1-mini Benchmark Runner
# Uses: Azure OpenAI API (high TPM quota)
# Framework: mini-swe-agent (baseline)
#
# Usage: ./run_azure_benchmark.sh [workers] [subset] [slice]
# Example: ./run_azure_benchmark.sh 512 verified
# Example: ./run_azure_benchmark.sh 64 verified "0:5"  # Test with first 5 tasks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKERS="${1:-64}"
SUBSET="${2:-verified}"
SLICE="${3:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/outputs/azure_gpt41mini_${SUBSET}_${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Azure OpenAI GPT-4.1-mini Benchmark Runner (mini-swe-agent)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check for Azure credentials
PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "$PARENT_ENV" ]; then
    set -a
    source "$PARENT_ENV"
    set +a
fi

# Verify Azure credentials
if [ -z "$AZURE_OPENAI_ENDPOINT" ] || [ -z "$AZURE_OPENAI_APIKEY" ]; then
    echo -e "${RED}ERROR: Azure OpenAI credentials not set${NC}"
    echo "Please ensure .env file has:"
    echo "  AZURE_OPENAI_ENDPOINT=..."
    echo "  AZURE_OPENAI_APIKEY=..."
    echo "  AZURE_DEPLOYMENT_NAME=..."
    exit 1
fi

echo -e "${GREEN}✓ Azure OpenAI credentials found${NC}"
echo "  Endpoint: ${AZURE_OPENAI_ENDPOINT}"
echo "  Deployment: ${AZURE_DEPLOYMENT_NAME:-dev-gpt-4.1-mini}"
echo ""

# Ensure mini-swe-agent is installed
echo -e "${YELLOW}Checking mini-swe-agent installation...${NC}"
export MSWEA_SILENT_STARTUP=1
if ! python -c "import minisweagent" 2>/dev/null; then
    echo -e "${YELLOW}Installing mini-swe-agent...${NC}"
    cd "$SCRIPT_DIR"
    pip install -e .
fi

# Ensure datasets is installed
if ! python -c "import datasets" 2>/dev/null; then
    echo -e "${YELLOW}Installing datasets...${NC}"
    pip install datasets
fi

echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Create config with Azure credentials from .env
CONFIG_FILE="$SCRIPT_DIR/src/minisweagent/config/azure_gpt41_mini.yaml"
TEMP_CONFIG="$OUTPUT_DIR/config.yaml"

# Copy base config and inject credentials
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$TEMP_CONFIG"
    # Update model name if deployment name is set
    if [ -n "$AZURE_DEPLOYMENT_NAME" ]; then
        sed -i "s|model_name:.*|model_name: \"${AZURE_DEPLOYMENT_NAME}\"|" "$TEMP_CONFIG"
    fi
    # Update api_base
    API_BASE="${AZURE_OPENAI_ENDPOINT%/openai/v1}"
    sed -i "s|api_base:.*|api_base: \"${API_BASE}\"|" "$TEMP_CONFIG"
    # Update api_version if set
    if [ -n "$AZURE_OPENAI_API_VERSION" ]; then
        sed -i "s|api_version:.*|api_version: \"${AZURE_OPENAI_API_VERSION}\"|" "$TEMP_CONFIG"
    fi
    # Add api_key to model_kwargs (litellm needs it in config or env var)
    # Check if api_key line exists (commented or not)
    if ! grep -q "^[[:space:]]*api_key:" "$TEMP_CONFIG"; then
        # Insert api_key after custom_llm_provider
        sed -i "/custom_llm_provider:/a\    api_key: \"${AZURE_OPENAI_APIKEY}\"" "$TEMP_CONFIG"
    else
        # Uncomment and update existing api_key line
        sed -i "s|# api_key:.*|api_key: \"${AZURE_OPENAI_APIKEY}\"|" "$TEMP_CONFIG"
        sed -i "s|^[[:space:]]*api_key:.*|    api_key: \"${AZURE_OPENAI_APIKEY}\"|" "$TEMP_CONFIG"
    fi
else
    echo -e "${RED}ERROR: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Log configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "  Model:       Azure OpenAI GPT-4.1-mini"
echo "  Framework:   mini-swe-agent (baseline)"
echo "  Subset:      $SUBSET"
echo "  Workers:     $WORKERS (high parallelism for Azure high TPM quota)"
if [ -n "$SLICE" ]; then
    echo "  Slice:       $SLICE (test mode)"
fi
echo "  Output:      $OUTPUT_DIR"
echo "  Config:      $TEMP_CONFIG"
echo ""

# Save config copy
cp "$TEMP_CONFIG" "$OUTPUT_DIR/config.yaml"

# Run benchmark
echo -e "${BLUE}Starting benchmark...${NC}"
echo "  Start time: $(date)"
echo ""

# Log file
LOG_FILE="$OUTPUT_DIR/benchmark.log"

# Set Azure environment variables for litellm
export AZURE_API_KEY="$AZURE_OPENAI_APIKEY"
export AZURE_API_BASE="${AZURE_OPENAI_ENDPOINT%/openai/v1}"
export AZURE_API_VERSION="${AZURE_OPENAI_API_VERSION:-2025-01-01-preview}"

# Build command
CMD="python -m minisweagent.run.extra.swebench \
    --subset \"$SUBSET\" \
    --split test \
    --workers \"$WORKERS\" \
    --config \"$TEMP_CONFIG\" \
    --output \"$OUTPUT_DIR\""

if [ -n "$SLICE" ]; then
    CMD="$CMD --slice \"$SLICE\""
fi

# Run the benchmark
eval "$CMD" 2>&1 | tee "$LOG_FILE"

EXITCODE=${PIPESTATUS[0]}

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

if [ $EXITCODE -eq 0 ]; then
    echo -e "${GREEN}✓ Benchmark completed successfully${NC}"
else
    echo -e "${RED}✗ Benchmark exited with code $EXITCODE${NC}"
fi

echo "  End time:   $(date)"
echo "  Output:     $OUTPUT_DIR"
echo "  Log:        $LOG_FILE"

# Show results summary if preds.json exists
if [ -f "$OUTPUT_DIR/preds.json" ]; then
    COMPLETED=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
    echo "  Completed:  $COMPLETED instances"
fi

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

