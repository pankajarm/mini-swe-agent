#!/bin/bash
# =============================================================================
# Master Orchestrator: Run Complete Ministral3-3B-SFT SWE-bench Workflow
# 
# This script orchestrates the complete workflow:
# 1. Start vLLM server
# 2. Run benchmark
# 3. Run evaluation
# 4. Upload to HuggingFace
# 
# Each step runs in its own screen session and can be monitored independently.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WORKERS="${1:-8}"
SUBSET="${2:-verified}"
SKIP_VLLM="${3:-}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Ministral3-3B-SFT Complete SWE-bench Workflow${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "This script will orchestrate the complete workflow:"
echo "  1. Start vLLM server (if not already running)"
echo "  2. Run benchmark"
echo "  3. Run evaluation (after benchmark completes)"
echo "  4. Upload to HuggingFace (after evaluation completes)"
echo ""
echo "Each step runs in its own screen session for safe disconnection."
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Workers:      $WORKERS"
echo "  Subset:       $SUBSET"
if [ -n "$SKIP_VLLM" ]; then
    echo "  vLLM:         Skip (assuming already running)"
fi
echo ""
echo "Monitor progress with: ./monitor_ministral_benchmark.sh"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# Step 1: Start vLLM server
if [ -z "$SKIP_VLLM" ]; then
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Step 1: Starting vLLM Server${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    
    if curl -s "http://localhost:8000/v1/models" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ vLLM server is already running${NC}"
    else
        echo "Starting vLLM server..."
        ./start_vllm_ministral.sh
        
        echo ""
        echo "Waiting for vLLM server to be ready..."
        for i in {1..60}; do
            if curl -s "http://localhost:8000/v1/models" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ vLLM server is ready${NC}"
                break
            fi
            echo -n "."
            sleep 5
        done
        echo ""
    fi
else
    echo ""
    echo -e "${YELLOW}Skipping vLLM startup (assuming already running)${NC}"
    if ! curl -s "http://localhost:8000/v1/models" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR] vLLM server is not running. Please start it first.${NC}"
        exit 1
    fi
fi

# Step 2: Run benchmark
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 2: Running Benchmark${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Starting benchmark in screen session..."
./run_ministral_benchmark.sh "$WORKERS" "$SUBSET"

echo ""
echo -e "${GREEN}✓ Benchmark started${NC}"
echo ""
echo "The benchmark is running in a screen session. You can:"
echo "  - Monitor: ./monitor_ministral_benchmark.sh"
echo "  - Attach:  screen -r ministral3_benchmark"
echo ""
echo -e "${YELLOW}Waiting for benchmark to complete...${NC}"
echo "(This may take several hours. You can disconnect and check back later.)"
echo ""
echo "To check status:"
echo "  ./monitor_ministral_benchmark.sh --once"
echo ""

# Wait for benchmark to complete (check every 5 minutes)
BENCH_SCREEN="ministral3_benchmark"
while screen -list 2>/dev/null | grep -q "$BENCH_SCREEN"; do
    echo -n "."
    sleep 300  # Check every 5 minutes
done

echo ""
echo -e "${GREEN}✓ Benchmark completed${NC}"

# Step 3: Run evaluation
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 3: Running Evaluation${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Starting evaluation..."
./run_ministral_evaluation.sh

echo ""
echo -e "${GREEN}✓ Evaluation started${NC}"
echo ""
echo "The evaluation is running in a screen session. You can:"
echo "  - Monitor: ./monitor_ministral_benchmark.sh"
echo "  - Attach:  screen -r ministral3_eval"
echo ""
echo -e "${YELLOW}Waiting for evaluation to complete...${NC}"

# Wait for evaluation to complete
EVAL_SCREEN="ministral3_eval"
while screen -list 2>/dev/null | grep -q "$EVAL_SCREEN"; do
    echo -n "."
    sleep 300  # Check every 5 minutes
done

echo ""
echo -e "${GREEN}✓ Evaluation completed${NC}"

# Step 4: Upload to HuggingFace
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Step 4: Uploading to HuggingFace${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Starting upload..."
./upload_ministral_to_hf.sh

echo ""
echo -e "${GREEN}✓ Upload started${NC}"
echo ""
echo "The upload is running in a screen session. You can:"
echo "  - Monitor: ./monitor_ministral_benchmark.sh"
echo "  - Attach:  screen -r ministral3_upload"
echo ""
echo -e "${YELLOW}Waiting for upload to complete...${NC}"

# Wait for upload to complete
UPLOAD_SCREEN="ministral3_upload"
while screen -list 2>/dev/null | grep -q "$UPLOAD_SCREEN"; do
    echo -n "."
    sleep 60  # Check every minute (uploads are faster)
done

echo ""
echo -e "${GREEN}✓ Upload completed${NC}"

# Final summary
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Workflow Complete!${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "All steps have completed successfully."
echo ""
echo "Results are available at:"
LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/ministral3_"* 2>/dev/null | head -1)
if [ -n "$LATEST_OUTPUT" ]; then
    echo "  Output:  $LATEST_OUTPUT"
    
    EVAL_DIR=$(find "$LATEST_OUTPUT" -type d -name "evaluation_*" 2>/dev/null | head -1)
    if [ -n "$EVAL_DIR" ] && [ -f "$EVAL_DIR/final_summary.json" ]; then
        RESOLVED=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('resolved', 0))" 2>/dev/null || echo "0")
        TOTAL=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('total', 0))" 2>/dev/null || echo "0")
        echo "  Resolved: $RESOLVED / $TOTAL ($(echo "scale=1; $RESOLVED * 100 / $TOTAL" | bc)%)"
    fi
fi
echo ""
echo "Dataset: https://huggingface.co/datasets/pankajmathur/ministral3-3b-sft-swebench-verified-traj"
echo ""

