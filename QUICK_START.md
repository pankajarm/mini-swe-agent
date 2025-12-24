# Quick Start Guide - mini-swe-agent Azure Benchmark

## TL;DR

Run SWE-bench verified 500 tasks using Azure OpenAI GPT-4.1-mini with high parallelism.

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent
./run_azure_in_screen.sh 512 verified
```

## Step-by-Step

### 1. Navigate to directory
```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent
```

### 2. Launch benchmark in screen
```bash
# Full run (500 tasks, 512 workers)
./run_azure_in_screen.sh 512 verified

# Or test with 5 tasks first
./run_azure_in_screen.sh 64 verified "0:5"
```

### 3. Monitor progress
```bash
# Quick status
./status.sh

# Live monitor (refreshes every 30s)
./monitor.sh

# Or attach to screen
screen -r mini-azure-gpt41mini-bench
```

### 4. Check results
```bash
# Find latest output
LATEST=$(ls -td outputs/azure_gpt41mini_* | head -1)

# Check completion count
python3 -c "import json; print(f\"Completed: {len(json.load(open('$LATEST/preds.json')))}\")"
```

## Expected Timeline

- **512 workers**: ~4 hours for 500 tasks
- **256 workers**: ~8 hours for 500 tasks
- **128 workers**: ~16 hours for 500 tasks

## Scaling Strategy

1. **Test first**: Run with `"0:5"` slice to verify setup
2. **Start small**: Begin with 128 workers
3. **Scale up**: Increase to 256, then 512 if rate limits allow

## Key Commands

```bash
# Launch
./run_azure_in_screen.sh 512 verified

# Monitor
./monitor.sh

# Status
./status.sh

# Attach to screen
screen -r mini-azure-gpt41mini-bench

# Kill session
screen -S mini-azure-gpt41mini-bench -X quit
```

## Output Location

Results saved to:
```
outputs/azure_gpt41mini_verified_TIMESTAMP/
├── preds.json          # Main predictions file
├── benchmark.log       # Full log
└── config.yaml        # Config used
```

## Comparison

This baseline run will be compared with:
- **live-swe-agent-benchmark** (already completed 500 tasks)
- **gepa-swe-agent** (to be run next)

All use the same:
- Model: Azure OpenAI GPT-4.1-mini
- API: Same endpoint and credentials
- Tasks: SWE-bench verified (500 tasks)

