# SWE-Agent Comparison Project — Next Steps

## Current Status Summary

### ✅ Completed
- **live-swe-agent-benchmark**: 54/500 resolved (10.8% resolve rate)
  - Uploaded to HuggingFace Dataset
  - All 500 instances submitted (100%)

### 🔄 Running
- **mini-swe-agent**: Running in screen session `mini-azure-full-bench`
  - Output: `outputs/azure_gpt41mini_full_20251224_221708/`
  - Expected completion: ~4 hours from start (22:17 UTC)
  - Monitor with: `./monitor_full_benchmark.sh` or `screen -r mini-azure-full-bench`

### ⏳ Pending
- **gepa-swe-agent**: Ready to launch
  - Script: `/home/ubuntu/us-east-1-nano-chat-exp/gepa-swe-agent/run_azure_benchmark.sh`
  - Config: `src/gepa_swe_agent/config/azure_gpt41_mini.yaml`

## Workflow After mini-swe-agent Completes

### Step 1: Evaluate mini-swe-agent Results

Once `preds.json` is generated (check with `./status_full_benchmark.sh`):

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent
./evaluate_results.sh
```

This will:
- Run SWE-bench evaluation harness on the predictions
- Calculate resolve rate and other metrics
- Display summary results

### Step 2: Launch gepa-swe-agent Benchmark

After mini-swe-agent evaluation is complete:

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/gepa-swe-agent
./run_azure_benchmark.sh 512 verified
```

Or run in screen session for safe disconnect:

```bash
screen -S gepa-azure-full-bench
cd /home/ubuntu/us-east-1-nano-chat-exp/gepa-swe-agent
./run_azure_benchmark.sh 512 verified
# Press Ctrl+A then D to detach
```

### Step 3: Compare All Three Agents

Once all three agents have results:

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent
./compare_agents.sh
```

This will display:
- Side-by-side comparison table
- Resolve rates for each agent
- Winner analysis
- File locations for detailed results

## Monitoring Tools

### mini-swe-agent (Current Run)
```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent

# Quick status
./status_full_benchmark.sh

# Live monitor (auto-refresh every 30s)
./monitor_full_benchmark.sh

# Attach to screen session
screen -r mini-azure-full-bench
```

### gepa-swe-agent (When Running)
```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/gepa-swe-agent

# Check if running
screen -ls | grep gepa

# Attach to monitor
screen -r gepa-azure-full-bench
```

## Evaluation Notes

### Evaluation Format
All agents generate `preds.json` files in SWE-bench standard format:
```json
{
  "instance_id": {
    "model_name_or_path": "...",
    "instance_id": "...",
    "model_patch": "..."
  }
}
```

### Evaluation Process
1. Use `swebench.harness.run_evaluation` (official SWE-bench harness)
2. Generates evaluation results JSON with:
   - `total_instances`
   - `submitted_instances`
   - `resolved_instances` (passed tests)
   - `unresolved_instances` (failed tests)
   - `error_instances`

### Resolve Rate Calculation
```
Resolve Rate = (resolved_instances / total_instances) × 100%
```

## Expected Timeline

- **mini-swe-agent**: ~4 hours total (started 22:17 UTC)
  - Check: `./status_full_benchmark.sh`
- **gepa-swe-agent**: ~4 hours (similar to other agents)
  - Launch after mini-swe-agent evaluation completes

## Configuration Consistency

All three agents use:
- **Model**: Azure OpenAI GPT-4.1-mini
- **Dataset**: SWE-bench Verified (500 instances)
- **Workers**: 512 (high parallelism for Azure TPM quota)
- **Same API endpoint/credentials** (from `.env` file)

## Troubleshooting

### If mini-swe-agent is still running but slow:
- Check Azure API quota/limits
- Verify workers are active: `ps aux | grep python | grep swebench`
- Monitor log file growth: `ls -lh outputs/azure_gpt41mini_full_*/benchmark.log`

### If evaluation fails:
- Ensure `swebench` is installed: `pip install swebench`
- Check predictions file format: `head -20 outputs/.../preds.json`
- Verify dataset access: `python -c "from datasets import load_dataset; load_dataset('princeton-nlp/SWE-bench_Verified')"`

### If comparison script shows missing results:
- Verify evaluation has run for each agent
- Check file paths in script match actual output directories
- Look for `*.eval_*.json` or `results.json` files in output directories

## Results Summary Table (To Be Filled)

| Agent | Status | Resolved | Total | Resolve Rate | Notes |
|-------|--------|----------|-------|--------------|-------|
| live-swe-agent-benchmark | ✅ | 54 | 500 | 10.8% | Uploaded to HF |
| mini-swe-agent | 🔄 | TBD | 500 | TBD | Running... |
| gepa-swe-agent | ⏳ | TBD | 500 | TBD | Ready to launch |

