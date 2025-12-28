#!/bin/bash
# =============================================================================
# Fix Error Instances for GPT-5-mini Benchmark
# Regenerates patches for 4 failed instances
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/outputs/gpt5mini_fix_errors_$(date +%Y%m%d_%H%M%S)"
WORKERS=4
SCREEN_NAME="gpt5mini_fix"

# Error instances to fix
ERROR_INSTANCES="django__django-13794|psf__requests-1142|sphinx-doc__sphinx-9591|sphinx-doc__sphinx-8721"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Fix GPT-5-mini Error Instances${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}Screen '$SCREEN_NAME' exists. Kill with: screen -S $SCREEN_NAME -X quit${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Azure GPT-5-mini credentials
export AZURE_OPENAI_ENDPOINT="https://sage-dev-v1.openai.azure.com/openai/v1/"
export AZURE_OPENAI_API_VERSION="2025-04-01-preview"
export AZURE_OPENAI_APIKEY="${AZURE_OPENAI_APIKEY}"
export AZURE_DEPLOYMENT_NAME="gpt-5-mini"

# Create config
CONFIG="$OUTPUT_DIR/config.yaml"
cat > "$CONFIG" << 'EOFCONFIG'
agent:
  system_template: |
    You are a helpful assistant that can interact multiple times with a computer shell to solve programming tasks.
    Your response must contain exactly ONE bash code block with ONE command (or commands connected with && or ||).
    Include a THOUGHT section before your command.
    
    <format_example>
    THOUGHT: Your reasoning here
    
    ```bash
    your_command_here
    ```
    </format_example>
  instance_template: |
    <pr_description>
    {{task}}
    </pr_description>
    
    Fix the issue described above by modifying source files in /testbed.
    
    IMPORTANT RULES:
    1. ONE bash command per response
    2. Use git diff format for patches
    3. Submit with: echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT && git add -A && git diff --cached
    
    Workflow:
    1. Explore the codebase
    2. Create reproduction script
    3. Make targeted fix
    4. Verify fix
    5. Submit
  action_observation_template: |
    <returncode>{{output.returncode}}</returncode>
    {% if output.output | length < 10000 -%}
    <output>{{ output.output -}}</output>
    {%- else -%}
    <output_head>{{ output.output[:5000] }}</output_head>
    <output_tail>{{ output.output[-5000:] }}</output_tail>
    {%- endif -%}
  format_error_template: |
    Provide EXACTLY ONE bash command in triple backticks.
  timeout_template: |
    Command timed out. Try another approach.
  step_limit: 250
  cost_limit: 100.

environment:
  cwd: "/testbed"
  timeout: 60
  env:
    PAGER: cat
    MANPAGER: cat
    LESS: -R
    PIP_PROGRESS_BAR: 'off'
    TQDM_DISABLE: '1'
  environment_class: docker

model:
  model_class: litellm
  model_name: "gpt-5-mini"
  model_kwargs:
    custom_llm_provider: "azure"
    api_base: "https://sage-dev-v1.openai.azure.com"
    api_key: "AZURE_KEY_PLACEHOLDER"
    api_version: "2025-04-01-preview"
    temperature: 1.0
    drop_params: true
  cost_tracking: ignore_errors
EOFCONFIG

sed -i "s|AZURE_KEY_PLACEHOLDER|${AZURE_OPENAI_APIKEY}|g" "$CONFIG"

echo -e "${YELLOW}Instances to fix:${NC}"
echo "  - django__django-13794"
echo "  - psf__requests-1142"
echo "  - sphinx-doc__sphinx-9591"
echo "  - sphinx-doc__sphinx-8721"
echo ""

# Create wrapper script
WRAPPER="$OUTPUT_DIR/run_fix.sh"
cat > "$WRAPPER" << EOFWRAP
#!/bin/bash
cd "$SCRIPT_DIR"

export AZURE_API_KEY="$AZURE_OPENAI_APIKEY"
export AZURE_API_BASE="https://sage-dev-v1.openai.azure.com"
export AZURE_API_VERSION="$AZURE_OPENAI_API_VERSION"
export MSWEA_COST_TRACKING="ignore_errors"
export MSWEA_SILENT_STARTUP=1

LOG="$OUTPUT_DIR/benchmark.log"

echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Fixing 4 Error Instances"
echo "  Started: \$(date)"
echo "═══════════════════════════════════════════════════════════════════════════"

python -m minisweagent.run.extra.swebench \\
    --subset verified \\
    --split test \\
    --workers $WORKERS \\
    --config "$CONFIG" \\
    --output "$OUTPUT_DIR" \\
    --filter "$ERROR_INSTANCES" \\
    2>&1 | tee "\$LOG"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Completed: \$(date)"
echo "═══════════════════════════════════════════════════════════════════════════"

if [ -f "$OUTPUT_DIR/preds.json" ]; then
    python3 -c "import json; d=json.load(open('$OUTPUT_DIR/preds.json')); print(f'Generated: {len(d)} patches')"
fi

echo "Press Enter to close..."
read
EOFWRAP
chmod +x "$WRAPPER"

# Save info
cat > "$OUTPUT_DIR/fix_info.json" << EOF
{
    "instances": ["django__django-13794", "psf__requests-1142", "sphinx-doc__sphinx-9591", "sphinx-doc__sphinx-8721"],
    "workers": $WORKERS,
    "start_time": "$(date -Iseconds)",
    "screen": "$SCREEN_NAME"
}
EOF

echo -e "${BLUE}Launching in screen...${NC}"
screen -dmS "$SCREEN_NAME" bash "$WRAPPER"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen '$SCREEN_NAME' started${NC}"
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $OUTPUT_DIR/benchmark.log"
    echo -e "${GREEN}Safe to disconnect.${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}Failed to start screen${NC}"
    exit 1
fi

