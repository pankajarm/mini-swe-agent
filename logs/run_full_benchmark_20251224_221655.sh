#!/bin/bash
# Wrapper script that runs inside screen session
# All output is logged to files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
cd "$SCRIPT_DIR"

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

# Create timestamped output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/outputs/azure_gpt41mini_full_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

# Log files
MAIN_LOG="$OUTPUT_DIR/benchmark.log"
STDOUT_LOG="$OUTPUT_DIR/stdout.log"
STDERR_LOG="$OUTPUT_DIR/stderr.log"
STATUS_LOG="$OUTPUT_DIR/status.log"

echo "═══════════════════════════════════════════════════════════════════════════" | tee -a "$MAIN_LOG"
echo "  Full Benchmark Run Started" | tee -a "$MAIN_LOG"
echo "  Timestamp: $(date)" | tee -a "$MAIN_LOG"
echo "  Output: $OUTPUT_DIR" | tee -a "$MAIN_LOG"
echo "  Workers: 512" | tee -a "$MAIN_LOG"
echo "═══════════════════════════════════════════════════════════════════════════" | tee -a "$MAIN_LOG"
echo ""

# Function to log status
log_status() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" | tee -a "$STATUS_LOG" "$MAIN_LOG"
}

# Function to check progress
check_progress() {
    if [ -f "$OUTPUT_DIR/preds.json" ]; then
        COUNT=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
        echo "$COUNT"
    else
        echo "0"
    fi
}

# Trap to log on exit
trap 'log_status "Benchmark process exited with code: $?"' EXIT

# Run benchmark with all output logged
log_status "Starting benchmark execution..."

# Run the benchmark, logging everything
./run_azure_benchmark.sh "512" "$SUBSET" > >(tee -a "$STDOUT_LOG" "$MAIN_LOG") 2> >(tee -a "$STDERR_LOG" "$MAIN_LOG" >&2)

EXITCODE=$?

log_status "Benchmark completed with exit code: $EXITCODE"

# Final status
if [ -f "$OUTPUT_DIR/preds.json" ]; then
    FINAL_COUNT=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
    log_status "Final count: $FINAL_COUNT instances completed"
else
    log_status "WARNING: preds.json not found"
fi

log_status "All logs saved to: $OUTPUT_DIR"
log_status "Benchmark finished at: $(date)"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Benchmark complete. Press Enter to close this screen session..."
echo "═══════════════════════════════════════════════════════════════════════════"
read
