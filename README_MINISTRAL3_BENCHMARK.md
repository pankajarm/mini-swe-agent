# Ministral3-3B-SFT SWE-bench Benchmark

Complete workflow scripts to run SWE-bench Verified benchmark on the Ministral3-3B-SFT model using mini-swe-agent.

## Overview

This workflow:
1. Starts vLLM server with the Ministral3-3B-SFT model
2. Runs SWE-bench Verified benchmark using mini-swe-agent
3. Evaluates results using SWE-bench evaluation harness
4. Uploads trajectories and results to HuggingFace dataset

All processes run in screen sessions for safe disconnection.

## Model

- **Model**: [pankajmathur/ministral3-3b-sft-openthoughts-merged](https://huggingface.co/pankajmathur/ministral3-3b-sft-openthoughts-merged)
- **Framework**: mini-swe-agent
- **Inference**: vLLM with OpenAI-compatible API
- **Benchmark**: SWE-bench Verified (500 instances)

## Quick Start

### Option 1: Run Complete Workflow (Automated)

Run all steps sequentially:

```bash
cd /home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent

# Full workflow (8 workers, verified subset)
./run_full_ministral_workflow.sh 8 verified

# Or skip vLLM if already running
./run_full_ministral_workflow.sh 8 verified skip
```

**Note**: This will wait for each step to complete before starting the next. You can disconnect and check back later.

### Option 2: Run Steps Manually (Recommended for Control)

Run each step independently for better control and monitoring:

#### Step 1: Start vLLM Server

```bash
./start_vllm_ministral.sh
```

This starts the vLLM server in a screen session (`vllm_ministral3`). The server will be available at `http://localhost:8000/v1`.

**Monitor**: 
```bash
screen -r vllm_ministral3
tail -f logs/vllm_ministral3.log
```

#### Step 2: Run Benchmark

```bash
# Full benchmark (8 workers, verified subset)
./run_ministral_benchmark.sh 8 verified

# Test run with first 5 instances
./run_ministral_benchmark.sh 8 verified "0:5"
```

This runs the benchmark in a screen session (`ministral3_benchmark`).

**Monitor**:
```bash
screen -r ministral3_benchmark
tail -f outputs/ministral3_verified_*/benchmark.log
```

#### Step 3: Run Evaluation

After benchmark completes, evaluate the results:

```bash
# Auto-detect latest predictions file
./run_ministral_evaluation.sh

# Or specify manually
./run_ministral_evaluation.sh outputs/ministral3_verified_*/preds.json
```

This runs evaluation in a screen session (`ministral3_eval`).

**Monitor**:
```bash
screen -r ministral3_eval
tail -f outputs/ministral3_verified_*/evaluation_*/eval.log
```

#### Step 4: Upload to HuggingFace

After evaluation completes, upload results:

```bash
# Auto-detect latest output directory
./upload_ministral_to_hf.sh

# Or specify manually
./upload_ministral_to_hf.sh outputs/ministral3_verified_*/ pankajmathur/ministral3-3b-sft-swebench-verified-traj
```

This runs upload in a screen session (`ministral3_upload`).

**Monitor**:
```bash
screen -r ministral3_upload
tail -f logs/upload_ministral_*.log
```

## Monitoring

### Single Command Monitor

Monitor all processes with a single command:

```bash
# Continuous monitoring (refreshes every 30s)
./monitor_ministral_benchmark.sh

# One-time status check
./monitor_ministral_benchmark.sh --once
```

### Individual Screen Sessions

```bash
# List all screen sessions
screen -ls

# Attach to specific session
screen -r vllm_ministral3        # vLLM server
screen -r ministral3_benchmark   # Benchmark
screen -r ministral3_eval        # Evaluation
screen -r ministral3_upload      # Upload

# Detach from screen: Press Ctrl+A, then D
# Kill screen session: screen -S <name> -X quit
```

### Check Progress

```bash
# Check benchmark progress
LATEST=$(ls -td outputs/ministral3_* | head -1)
python3 -c "import json; print(f'Completed: {len(json.load(open(\"$LATEST/preds.json\")))} instances')"

# Check evaluation results
EVAL_DIR=$(find outputs -type d -name "evaluation_*" | head -1)
cat "$EVAL_DIR/final_summary.json" 2>/dev/null || echo "Evaluation not complete yet"
```

## Configuration

### Environment Variables

Optional environment variables:

- `HF_TOKEN` or `HUGGINGFACE_TOKEN`: HuggingFace token for uploads
- `HF_HOME`: HuggingFace cache directory (default: uses docker-cache if available)
- `DOCKER_CACHE_DIR`: Docker cache directory (default: `/home/ubuntu/us-east-1-nano-chat-exp/docker-cache`)

### Benchmark Settings

Edit `run_ministral_benchmark.sh` to modify:
- `WORKERS`: Number of parallel workers (default: 8)
- `SUBSET`: SWE-bench subset (default: "verified")
- `VLLM_PORT`: vLLM server port (default: 8000)

### vLLM Settings

Edit `start_vllm_ministral.sh` to modify:
- `MODEL_ID`: HuggingFace model ID
- `NUM_GPUS`: Tensor parallel size (auto-detected)
- `GPU_MEMORY_UTILIZATION`: GPU memory usage (default: 0.95)
- `MAX_MODEL_LEN`: Maximum sequence length (default: 32768)

## Output Structure

```
outputs/ministral3_verified_YYYYMMDD_HHMMSS/
├── preds.json                    # Predictions file
├── config.yaml                   # Configuration used
├── benchmark.log                 # Benchmark log
├── <instance_id>/                # Per-instance trajectories
│   └── <instance_id>.traj.json
└── evaluation_YYYYMMDD_HHMMSS/   # Evaluation results
    ├── preds_swebench.json       # SWE-bench format predictions
    ├── eval.log                  # Evaluation log
    ├── final_summary.json        # Evaluation summary
    └── *.json                    # Detailed evaluation results
```

## Troubleshooting

### vLLM Server Not Starting

- Check GPU availability: `nvidia-smi`
- Check if port 8000 is already in use: `lsof -i :8000`
- Check logs: `tail -f logs/vllm_ministral3.log`

### Benchmark Fails

- Verify vLLM server is running: `curl http://localhost:8000/v1/models`
- Check benchmark log: `tail -f outputs/ministral3_*/benchmark.log`
- Ensure mini-swe-agent is installed: `pip install -e .`

### Evaluation Fails

- Verify predictions file exists: `ls outputs/ministral3_*/preds.json`
- Check evaluation log: `tail -f outputs/ministral3_*/evaluation_*/eval.log`
- Ensure SWE-bench is installed: `pip install swe-bench`

### Upload Fails

- Verify HuggingFace token is set: `echo $HF_TOKEN`
- Check upload log: `tail -f logs/upload_ministral_*.log`
- Verify trajectories exist: `find outputs/ministral3_* -name "*.traj.json" | wc -l`

## Expected Timeline

- **vLLM Startup**: ~2-5 minutes (model loading)
- **Benchmark** (500 instances, 8 workers): ~12-24 hours
- **Evaluation** (500 instances, 16 workers): ~2-4 hours
- **Upload**: ~30 minutes - 1 hour

## Docker Cache

The scripts automatically use the docker cache if available at:
`/home/ubuntu/us-east-1-nano-chat-exp/docker-cache`

This speeds up Docker image pulls for SWE-bench evaluation.

## HuggingFace Dataset

Results are uploaded to:
`https://huggingface.co/datasets/pankajmathur/ministral3-3b-sft-swebench-verified-traj`

The dataset includes:
- Trajectory files (`.traj.json`)
- Predictions file (`preds.json`)
- Evaluation results
- README with benchmark results

## Related

- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)
- [SWE-bench](https://www.swebench.com/)
- [Ministral3-3B-SFT Model](https://huggingface.co/pankajmathur/ministral3-3b-sft-openthoughts-merged)

