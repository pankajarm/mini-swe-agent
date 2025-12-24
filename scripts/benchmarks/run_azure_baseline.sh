#!/bin/bash
# mini-swe-agent Baseline Benchmark with Azure OpenAI GPT-4.1-mini
# This script runs mini-swe-agent as the baseline for comparison

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKERS="${1:-24}"
SUBSET="${2:-verified}"
SLICE="${3:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$SCRIPT_DIR/outputs/azure_gpt41mini_baseline_${SUBSET}_${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  mini-swe-agent Baseline Benchmark (Azure OpenAI GPT-4.1-mini)${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Load Azure credentials from .env
ENV_FILE="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo -e "${GREEN}✓ Loaded Azure credentials from $ENV_FILE${NC}"
else
    echo -e "${YELLOW}⚠ Warning: .env file not found at $ENV_FILE${NC}"
    echo "  Will use environment variables if set"
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

# Update config with Azure credentials from .env
CONFIG_FILE="$SCRIPT_DIR/src/minisweagent/config/azure_gpt41_mini.yaml"
TEMP_CONFIG="$OUTPUT_DIR/config.yaml"

# Create config with credentials from .env
cat > "$TEMP_CONFIG" <<EOF
# mini-swe-agent Azure config (generated from .env)
# Original: $CONFIG_FILE

agent:
  system_template: |
    You are a helpful assistant that can interact multiple times with a computer shell to solve programming tasks.
    Your response must contain exactly ONE bash code block with ONE command (or commands connected with && or ||).

    Include a THOUGHT section before your command where you explain your reasoning process.
    Format your response as shown in <format_example>.

    <format_example>
    THOUGHT: Your reasoning and analysis here

    \`\`\`bash
    your_command_here
    \`\`\`
    </format_example>

    Failure to follow these rules will cause your response to be rejected.
  instance_template: |
    <pr_description>
    Consider the following PR description:
    {{task}}
    </pr_description>

    <instructions>
    # Task Instructions

    ## Overview
    You're a software engineer interacting continuously with a computer by submitting commands.
    You'll be helping implement necessary changes to meet requirements in the PR description.
    Your task is specifically to make changes to non-test files in the current directory in order to fix the issue described in the PR description in a way that is general and consistent with the codebase.

    IMPORTANT: This is an interactive process where you will think and issue ONE command, see its result, then think and issue your next command.

    For each response:
    1. Include a THOUGHT section explaining your reasoning and what you're trying to accomplish
    2. Provide exactly ONE bash command to execute

    ## Important Boundaries
    - MODIFY: Regular source code files in /testbed (this is the working directory for all your subsequent commands)
    - DO NOT MODIFY: Tests, configuration files (pyproject.toml, setup.cfg, etc.)

    ## Recommended Workflow
    1. Analyze the codebase by finding and reading relevant files
    2. Create a script to reproduce the issue
    3. Edit the source code to resolve the issue
    4. Verify your fix works by running your script again
    5. Test edge cases to ensure your fix is robust

    ## Command Execution Rules
    You are operating in an environment where
    1. You write a single command
    2. The system executes that command in a subshell
    3. You see the result
    4. You write your next command

    Each response should include:
    1. A **THOUGHT** section where you explain your reasoning and plan
    2. A single bash code block with your command

    Format your responses like this:

    <format_example>
    THOUGHT: Here I explain my reasoning process, analysis of the current situation,
    and what I'm trying to accomplish with the command below.

    \`\`\`bash
    your_command_here
    \`\`\`
    </format_example>

    Commands must be specified in a single bash code block:

    \`\`\`bash
    your_command_here
    \`\`\`

    **CRITICAL REQUIREMENTS:**
    - Your response SHOULD include a THOUGHT section explaining your reasoning
    - Your response MUST include EXACTLY ONE bash code block
    - This bash block MUST contain EXACTLY ONE command (or a set of commands connected with && or ||)
    - If you include zero or multiple bash blocks, or no command at all, YOUR RESPONSE WILL FAIL
    - Do NOT try to run multiple independent commands in separate blocks in one response
    - Directory or environment variable changes are not persistent. Every action is executed in a new subshell.
    - However, you can prefix any action with \`MY_ENV_VAR=MY_VALUE cd /path/to/working/dir && ...\` or write/load environment variables from files

    Example of a CORRECT response:
    <example_response>
    THOUGHT: I need to understand the structure of the repository first. Let me check what files are in the current directory to get a better understanding of the codebase.

    \`\`\`bash
    ls -la
    \`\`\`
    </example_response>

    Example of an INCORRECT response:
    <example_response>
    THOUGHT: I need to examine the codebase and then look at a specific file. I'll run multiple commands to do this.

    \`\`\`bash
    ls -la
    \`\`\`

    Now I'll read the file:

    \`\`\`bash
    cat file.txt
    \`\`\`
    </example_response>

    If you need to run multiple commands, either:
    1. Combine them in one block using && or ||
    \`\`\`bash
    command1 && command2 || echo "Error occurred"
    \`\`\`

    2. Wait for the first command to complete, see its output, then issue the next command in your following response.

    ## Environment Details
    - You have a full Linux shell environment
    - Always use non-interactive flags (-y, -f) for commands
    - Avoid interactive tools like vi, nano, or any that require user input
    - If a command isn't available, you can install it

    ## Useful Command Examples

    ### Create a new file:
    \`\`\`bash
    cat <<'EOF' > newfile.py
    import numpy as np
    hello = "world"
    print(hello)
    EOF
    \`\`\`

    ### Edit files with sed:
    \`\`\`bash
    # Replace all occurrences
    sed -i 's/old_string/new_string/g' filename.py

    # Replace only first occurrence
    sed -i 's/old_string/new_string/' filename.py

    # Replace first occurrence on line 1
    sed -i '1s/old_string/new_string/' filename.py

    # Replace all occurrences in lines 1-10
    sed -i '1,10s/old_string/new_string/g' filename.py
    \`\`\`

    ### View file content:
    \`\`\`bash
    # View specific lines with numbers
    nl -ba filename.py | sed -n '10,20p'
    \`\`\`

    ### Any other command you want to run
    \`\`\`bash
    anything
    \`\`\`

    ## Submission
    When you've completed your work (reading, editing, testing), and cannot make further progress
    issue exactly the following command:

    \`\`\`bash
    echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT && git add -A && git diff --cached
    \`\`\`

    This command will submit your work.
    You cannot continue working (reading, editing, testing) in any way on this task after submitting.
    </instructions>
  action_observation_template: |
    <returncode>{{output.returncode}}</returncode>
    {% if output.output | length < 10000 -%}
    <output>
    {{ output.output -}}
    </output>
    {%- else -%}
    <warning>
    The output of your last command was too long.
    Please try a different command that produces less output.
    If you're looking at a file you can try use head, tail or sed to view a smaller number of lines selectively.
    If you're using grep or find and it produced too much output, you can use a more selective search pattern.
    If you really need to see something from the full command's output, you can redirect output to a file and then search in that file.
    </warning>
    {%- set elided_chars = output.output | length - 10000 -%}
    <output_head>
    {{ output.output[:5000] }}
    </output_head>
    <elided_chars>
    {{ elided_chars }} characters elided
    </elided_chars>
    <output_tail>
    {{ output.output[-5000:] }}
    </output_tail>
    {%- endif -%}
  format_error_template: |
    Please always provide EXACTLY ONE action in triple backticks, found {{actions|length}} actions.

    Please format your action in triple backticks as shown in <response_example>.

    <response_example>
    Here are some thoughts about why you want to perform the action.

    \`\`\`bash
    <action>
    \`\`\`
    </response_example>

    If you have completed your assignment, please consult the first message about how to
    submit your solution (you will not be able to continue working on this task after that).
  timeout_template: |
    The last command <command>{{action['action']}}</command> timed out and has been killed.
    The output of the command was:
    {% if output | length < 10000 -%}
    <output>
    {{output}}
    </output>
    {%- else -%}
    <warning>Output was too long and has been truncated.</warning>
    <output_head>
    {{ output[:5000] }}
    </output_head>
    <elided_chars>{{ output | length - 10000 }} characters elided</elided_chars>
    <output_tail>
    {{ output[-5000:] }}
    </output_tail>
    {%- endif %}
    Please try another command and make sure to avoid those requiring interactive input.
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
  model_name: "${AZURE_DEPLOYMENT_NAME:-dev-gpt-4.1-mini}"
  model_kwargs:
    custom_llm_provider: "azure"
    api_base: "${AZURE_OPENAI_ENDPOINT%/openai/v1}"
    api_key: "${AZURE_OPENAI_APIKEY}"
    api_version: "${AZURE_OPENAI_API_VERSION:-2025-01-01-preview}"
    temperature: 0.0
  cost_tracking: ignore_errors
EOF

# Log configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "  Model:       Azure OpenAI GPT-4.1-mini"
echo "  Framework:   mini-swe-agent (baseline)"
echo "  Subset:      $SUBSET"
echo "  Workers:     $WORKERS"
if [ -n "$SLICE" ]; then
    echo "  Slice:       $SLICE (test mode)"
fi
echo "  Output:      $OUTPUT_DIR"
echo "  Config:      $TEMP_CONFIG"
echo ""

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

