#!/bin/bash
cd "/home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent"

# Load Azure credentials from .env
PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "$PARENT_ENV" ]; then
    set -a
    source "$PARENT_ENV"
    set +a
fi

# Set Azure environment variables for litellm
export AZURE_API_KEY="$AZURE_OPENAI_APIKEY"
export AZURE_API_BASE="${AZURE_OPENAI_ENDPOINT%/openai/v1}"
export AZURE_API_VERSION="${AZURE_OPENAI_API_VERSION:-2025-01-01-preview}"

# Run the benchmark
./run_azure_benchmark.sh 8 verified 0:5

# Keep screen alive after completion to view results
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Benchmark complete. Press Enter to close this screen session..."
echo "═══════════════════════════════════════════════════════════════════════════"
read
