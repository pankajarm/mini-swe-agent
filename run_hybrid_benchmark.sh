#!/bin/bash
# =============================================================================
# Run Hybrid Agent Benchmark in Screen Session
# =============================================================================
# Convenience script to run hybrid agent benchmark with screen session
#
# Usage:
#   ./run_hybrid_benchmark.sh [workers] [subset] [slice]
#
# Example:
#   ./run_hybrid_benchmark.sh 64 verified
#   ./run_hybrid_benchmark.sh 32 verified "0:10"  # Test with first 10 tasks
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WORKERS="${1:-64}"
SUBSET="${2:-verified}"
SLICE="${3:-}"
SCREEN_NAME="hybrid-agent-benchmark"

# Build command
if [ -n "$SLICE" ]; then
    COMMAND="./run_azure_benchmark.sh $WORKERS $SUBSET \"$SLICE\""
else
    COMMAND="./run_azure_benchmark.sh $WORKERS $SUBSET"
fi

# Run in screen session
./scripts/run_in_screen.sh "$SCREEN_NAME" "$COMMAND"

