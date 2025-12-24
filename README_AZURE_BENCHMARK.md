# mini-swe-agent Azure Benchmark

End-to-end scripts for running SWE-bench verified benchmark using Azure OpenAI GPT-4.1-mini.

## Quick Start

### Run in Screen Session (Recommended)

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent

# Full benchmark with 512 workers (like live-swe-agent run)
./run_azure_in_screen.sh 512 verified

# Test run with 5 instances
./run_azure_in_screen.sh 64 verified "0:5"
```

### Run Directly

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent

# Full benchmark
./run_azure_benchmark.sh 512 verified

# Test run
./run_azure_benchmark.sh 64 verified "0:5"
```

## Scripts

### Main Scripts

1. **`run_azure_benchmark.sh`** - Main benchmark runner
   - Usage: `./run_azure_benchmark.sh [workers] [subset] [slice]`
   - Example: `./run_azure_benchmark.sh 512 verified`

2. **`run_azure_in_screen.sh`** - Launch benchmark in detached screen session
   - Usage: `./run_azure_in_screen.sh [workers] [subset] [slice]`
   - Example: `./run_azure_in_screen.sh 512 verified`
   - Screen session name: `mini-azure-gpt41mini-bench`

### Helper Scripts

3. **`status.sh`** - Quick status check
   - Shows screen session status and latest output directory
   - Shows completed instance count

4. **`monitor.sh`** - Live progress monitor
   - Refreshes every 30 seconds
   - Shows completion count, rate, and recent log entries
   - Press Ctrl+C to stop

## Configuration

### Azure Credentials

Credentials are loaded from:
```
/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env
```

Required variables:
- `AZURE_OPENAI_ENDPOINT`
- `AZURE_OPENAI_APIKEY`
- `AZURE_DEPLOYMENT_NAME` (default: `dev-gpt-4.1-mini`)
- `AZURE_OPENAI_API_VERSION` (default: `2025-01-01-preview`)

### Config File

The config file is automatically generated with credentials injected:
- Base config: `src/minisweagent/config/azure_gpt41_mini.yaml`
- Runtime config: `outputs/azure_gpt41mini_verified_TIMESTAMP/config.yaml`

## Screen Commands

```bash
# Attach to running benchmark
screen -r mini-azure-gpt41mini-bench

# Detach from screen (while attached)
Ctrl+A, then D

# Kill benchmark session
screen -S mini-azure-gpt41mini-bench -X quit

# List all screen sessions
screen -list
```

## Output Structure

Each run creates a timestamped directory:
```
outputs/azure_gpt41mini_verified_TIMESTAMP/
├── config.yaml          # Configuration used
├── benchmark.log         # Full execution log
├── preds.json           # Predictions in SWE-bench format
├── exit_statuses_*.yaml # Exit statuses for each instance
└── */                    # Per-instance trajectory directories
```

## Monitoring

### Quick Status
```bash
./status.sh
```

### Live Monitor
```bash
./monitor.sh
```

### Check Logs
```bash
# Find latest output
LATEST=$(ls -td outputs/azure_gpt41mini_* | head -1)

# View log
tail -f "$LATEST/benchmark.log"

# Check completion count
python3 -c "import json; print(len(json.load(open('$LATEST/preds.json'))))"
```

## Scaling Strategy

Based on the live-swe-agent-benchmark run:

1. **Start with 128 workers** - Test the setup
2. **Scale to 256 workers** - If rate limits are manageable
3. **Scale to 512 workers** - For maximum throughput (75K RPM, 7.5M TPM)

Expected performance:
- **500 tasks in ~4 hours** with 512 workers
- **~120 tasks/hour** average rate
- **Rate limit errors expected** at high parallelism (handled gracefully)

## Comparison with live-swe-agent-benchmark

Both use the same:
- Azure OpenAI GPT-4.1-mini model
- Same API endpoint and credentials
- Same parallelism strategy
- Same output format

Key difference:
- **mini-swe-agent**: Baseline with standard prompts
- **live-swe-agent-benchmark**: Self-evolving tool creation prompts

## Troubleshooting

### Rate Limit Errors
- Expected at high parallelism (512 workers)
- mini-swe-agent handles retries automatically
- Check logs for retry patterns

### Screen Session Issues
```bash
# Kill stuck session
screen -S mini-azure-gpt41mini-bench -X quit

# Check if process is running
ps aux | grep minisweagent
```

### Credential Issues
```bash
# Verify .env file exists
cat /home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env | grep AZURE

# Test credentials
export AZURE_API_KEY="your-key"
export AZURE_API_BASE="https://sage-dev-2.openai.azure.com"
python -c "import litellm; print(litellm.completion(model='dev-gpt-4.1-mini', messages=[{'role':'user','content':'test'}]))"
```

## Next Steps After Benchmark

1. **Wait for completion** - Monitor with `./monitor.sh`
2. **Check results** - Review `preds.json` in output directory
3. **Run evaluation** - Use SWE-bench evaluation harness
4. **Compare with live-swe-agent** - Compare resolution rates

