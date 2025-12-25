#!/bin/bash
# Full Benchmark Launcher with Screen Session
# Runs 500-task benchmark in detached screen with full logging
#
# Usage: ./run_full_benchmark_screen.sh [workers]
# Example: ./run_full_benchmark_screen.sh 512

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKERS="${1:-512}"
SUBSET="verified"
SCREEN_NAME="mini-azure-full-bench"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Full Benchmark Launcher (500 tasks, Screen Session)${NC}"
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
        sleep 2
    else
        echo "Exiting. Attach to existing session with: screen -r $SCREEN_NAME"
        exit 0
    fi
fi

# Create logs directory
mkdir -p "$SCRIPT_DIR/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WRAPPER_SCRIPT="$SCRIPT_DIR/logs/run_full_benchmark_${TIMESTAMP}.sh"

# Create wrapper script that runs in screen
cat > "$WRAPPER_SCRIPT" << 'EOFWRAPPER'
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
echo "  Workers: $WORKERS" | tee -a "$MAIN_LOG"
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
./run_azure_benchmark.sh "$WORKERS" "$SUBSET" > >(tee -a "$STDOUT_LOG" "$MAIN_LOG") 2> >(tee -a "$STDERR_LOG" "$MAIN_LOG" >&2)

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
EOFWRAPPER

# Inject WORKERS variable into wrapper
sed -i "s|\$WORKERS|$WORKERS|g" "$WRAPPER_SCRIPT"
chmod +x "$WRAPPER_SCRIPT"

# Launch screen session
echo -e "${GREEN}Launching full benchmark in screen session: $SCREEN_NAME${NC}"
echo ""
echo "Configuration:"
echo "  Model:    Azure OpenAI GPT-4.1-mini"
echo "  Tasks:    500 (full verified subset)"
echo "  Workers:  $WORKERS"
echo "  Screen:   $SCREEN_NAME"
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
    echo "  Monitor progress:      ./monitor_full_benchmark.sh"
    echo "  Check status:          ./status_full_benchmark.sh"
    echo "  Attach to session:     screen -r $SCREEN_NAME"
    echo "  Detach from session:   Ctrl+A, then D"
    echo "  Kill session:          screen -S $SCREEN_NAME -X quit"
    echo ""
    echo "  Logs will be in: outputs/azure_gpt41mini_full_TIMESTAMP/"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}✗ Failed to start screen session${NC}"
    exit 1
fi

