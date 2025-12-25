#!/bin/bash
# Compare results from all three SWE agents
# Usage: ./compare_agents.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  SWE-Agent Comparison: Azure GPT-4.1-mini Results${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Paths to results
BASE_DIR="/home/ubuntu/us-east-1-nano-chat-exp"

# 1. live-swe-agent-benchmark (from HuggingFace or local)
LIVE_RESULTS_DIR="$BASE_DIR/swe-bench-huggingface-models/live-swe-agent-benchmark/outputs"
LIVE_EVAL_FILE=$(find "$LIVE_RESULTS_DIR" -name "*.eval_*.json" -type f 2>/dev/null | head -1)

# 2. mini-swe-agent
MINI_RESULTS_DIR="$SCRIPT_DIR/outputs"
MINI_EVAL_FILE=$(find evaluation_results -name "*.json" -type f 2>/dev/null | grep -E "(results|eval)" | head -1)

# 3. gepa-swe-agent
GEPA_RESULTS_DIR="$BASE_DIR/gepa-swe-agent/outputs"
GEPA_EVAL_FILE=$(find "$GEPA_RESULTS_DIR" -name "*.json" -type f 2>/dev/null | grep -E "(results|eval|summary)" | head -1)

# Function to extract results from evaluation file
extract_results() {
    local file="$1"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "0 0 0 0"
        return
    fi
    
    python3 << PYEOF
import json
import sys

try:
    with open("$file") as f:
        data = json.load(f)
    
    total = data.get('total_instances', 500)
    submitted = data.get('submitted_instances', 0)
    resolved = data.get('resolved_instances', 0)
    unresolved = data.get('unresolved_instances', 0)
    
    # For gepa-swe-agent summary format
    if 'resolved' in data and 'total' in data:
        resolved = data.get('resolved', 0)
        total = data.get('total', 500)
        submitted = data.get('submitted', resolved)  # Assume all resolved were submitted
    
    print(f"{total} {submitted} {resolved} {unresolved}")
except Exception as e:
    print("0 0 0 0", file=sys.stderr)
PYEOF
}

# Extract results for each agent
echo -e "${CYAN}Loading results...${NC}"
LIVE_RESULTS=($(extract_results "$LIVE_EVAL_FILE"))
MINI_RESULTS=($(extract_results "$MINI_EVAL_FILE"))
GEPA_RESULTS=($(extract_results "$GEPA_EVAL_FILE"))

LIVE_TOTAL=${LIVE_RESULTS[0]:-0}
LIVE_SUBMITTED=${LIVE_RESULTS[1]:-0}
LIVE_RESOLVED=${LIVE_RESULTS[2]:-0}
LIVE_UNRESOLVED=${LIVE_RESULTS[3]:-0}

MINI_TOTAL=${MINI_RESULTS[0]:-0}
MINI_SUBMITTED=${MINI_RESULTS[1]:-0}
MINI_RESOLVED=${MINI_RESULTS[2]:-0}
MINI_UNRESOLVED=${MINI_RESULTS[3]:-0}

GEPA_TOTAL=${GEPA_RESULTS[0]:-0}
GEPA_SUBMITTED=${GEPA_RESULTS[1]:-0}
GEPA_RESOLVED=${GEPA_RESULTS[2]:-0}
GEPA_UNRESOLVED=${GEPA_RESULTS[3]:-0}

# Calculate rates
if [ "$LIVE_TOTAL" -gt 0 ]; then
    LIVE_RATE=$(python3 -c "resolved=${LIVE_RESOLVED}; total=${LIVE_TOTAL}; print(f'{resolved/total*100:.1f}')" 2>/dev/null || echo "0.0")
else
    LIVE_RATE="0.0"
fi

if [ "$MINI_TOTAL" -gt 0 ]; then
    MINI_RATE=$(python3 -c "resolved=${MINI_RESOLVED}; total=${MINI_TOTAL}; print(f'{resolved/total*100:.1f}')" 2>/dev/null || echo "0.0")
else
    MINI_RATE="0.0"
fi

if [ "$GEPA_TOTAL" -gt 0 ]; then
    GEPA_RATE=$(python3 -c "resolved=${GEPA_RESOLVED}; total=${GEPA_TOTAL}; print(f'{resolved/total*100:.1f}')" 2>/dev/null || echo "0.0")
else
    GEPA_RATE="0.0"
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Comparison Results${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Print comparison table
printf "%-35s %12s %12s %10s %10s\n" "Agent" "Resolved" "Submitted" "Total" "Rate"
echo "────────────────────────────────────────────────────────────────────────────────────"

# live-swe-agent-benchmark
if [ "$LIVE_TOTAL" -gt 0 ]; then
    STATUS="${GREEN}✓${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s%%\n" \
        "live-swe-agent-benchmark" \
        "${LIVE_RESOLVED}/${LIVE_TOTAL}" \
        "${LIVE_SUBMITTED}/${LIVE_TOTAL}" \
        "$LIVE_TOTAL" \
        "$LIVE_RATE"
else
    STATUS="${YELLOW}⚠${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s\n" \
        "live-swe-agent-benchmark" \
        "N/A" "N/A" "N/A" "N/A"
fi

# mini-swe-agent
if [ "$MINI_TOTAL" -gt 0 ]; then
    STATUS="${GREEN}✓${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s%%\n" \
        "mini-swe-agent" \
        "${MINI_RESOLVED}/${MINI_TOTAL}" \
        "${MINI_SUBMITTED}/${MINI_TOTAL}" \
        "$MINI_TOTAL" \
        "$MINI_RATE"
else
    STATUS="${YELLOW}⏳${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s\n" \
        "mini-swe-agent" \
        "Running..." "Running..." "500" "TBD"
fi

# gepa-swe-agent
if [ "$GEPA_TOTAL" -gt 0 ]; then
    STATUS="${GREEN}✓${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s%%\n" \
        "gepa-swe-agent" \
        "${GEPA_RESOLVED}/${GEPA_TOTAL}" \
        "${GEPA_SUBMITTED}/${GEPA_TOTAL}" \
        "$GEPA_TOTAL" \
        "$GEPA_RATE"
else
    STATUS="${YELLOW}⏳${NC}"
    printf "${STATUS} %-32s %11s %11s %9s %9s\n" \
        "gepa-swe-agent" \
        "Pending" "Pending" "500" "TBD"
fi

echo "────────────────────────────────────────────────────────────────────────────────────"
echo ""

# Show file locations
echo -e "${CYAN}Results File Locations:${NC}"
echo "  live-swe-agent: ${LIVE_EVAL_FILE:-Not found}"
echo "  mini-swe-agent: ${MINI_EVAL_FILE:-Not found}"
echo "  gepa-swe-agent: ${GEPA_EVAL_FILE:-Not found}"
echo ""

# Determine winner
if [ "$LIVE_TOTAL" -gt 0 ] && [ "$MINI_TOTAL" -gt 0 ] && [ "$GEPA_TOTAL" -gt 0 ]; then
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Winner Analysis${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    python3 << PYEOF
live_rate = float("${LIVE_RATE}")
mini_rate = float("${MINI_RATE}")
gepa_rate = float("${GEPA_RATE}")

rates = [
    ("live-swe-agent-benchmark", live_rate, ${LIVE_RESOLVED}),
    ("mini-swe-agent", mini_rate, ${MINI_RESOLVED}),
    ("gepa-swe-agent", gepa_rate, ${GEPA_RESOLVED}),
]

# Sort by resolve rate
sorted_agents = sorted(rates, key=lambda x: x[1], reverse=True)

print(f"🥇 {sorted_agents[0][0]}: {sorted_agents[0][1]:.1f}% ({sorted_agents[0][2]} resolved)")
if len(sorted_agents) > 1:
    print(f"🥈 {sorted_agents[1][0]}: {sorted_agents[1][1]:.1f}% ({sorted_agents[1][2]} resolved)")
if len(sorted_agents) > 2:
    print(f"🥉 {sorted_agents[2][0]}: {sorted_agents[2][1]:.1f}% ({sorted_agents[2][2]} resolved)")
PYEOF
fi

echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"

