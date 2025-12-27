#!/bin/bash
# =============================================================================
# Monitoring Script for SWE-bench Benchmark
# - Monitors evaluation and retry processes
# - Periodically uploads results to HuggingFace
# - Logs everything to files
# - Safe to disconnect
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/outputs/azure_gpt41mini_verified_20251224_221708"
LOG_DIR="$OUTPUT_DIR/monitor_logs"
UPLOAD_INTERVAL=1200  # Upload every 20 minutes
REPO_NAME="mini-swe-agent-azure-gpt41mini-swebench-verified"

# Create log directory
mkdir -p "$LOG_DIR"

# Log file
MONITOR_LOG="$LOG_DIR/monitor_$(date +%Y%m%d_%H%M%S).log"

# Load HuggingFace token
TOKEN=$(grep HUGGINGFACE_WRITE_TOKEN /home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
export HUGGINGFACE_WRITE_TOKEN="$TOKEN"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MONITOR_LOG"
}

log "═══════════════════════════════════════════════════════════════════════════"
log "  Monitor Started"
log "  Output: $OUTPUT_DIR"
log "  Log: $MONITOR_LOG"
log "  Upload interval: ${UPLOAD_INTERVAL}s"
log "═══════════════════════════════════════════════════════════════════════════"

# Function to check process status
check_processes() {
    log "--- Process Status ---"
    
    # Check evaluation
    if pgrep -f "swebench.harness.run_evaluation" > /dev/null; then
        EVAL_STATUS="Running"
    else
        EVAL_STATUS="Stopped"
    fi
    log "Evaluation: $EVAL_STATUS"
    
    # Check retry
    if pgrep -f "minisweagent.*swebench" > /dev/null; then
        RETRY_STATUS="Running"
    else
        RETRY_STATUS="Stopped"
    fi
    log "Error Retry: $RETRY_STATUS"
    
    # Get prediction counts
    PREDS=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
    VALID=$(python3 -c "
import json
with open('$OUTPUT_DIR/preds.json') as f:
    preds = json.load(f)
valid = sum(1 for p in preds.values() if p.get('model_patch', '') and not p.get('model_patch', '').startswith(\"Command '\"))
print(valid)
" 2>/dev/null || echo "0")
    
    log "Predictions: $PREDS/500, Valid: $VALID"
    
    # Check evaluation results if available
    EVAL_LOG=$(ls -t "$OUTPUT_DIR"/evaluation*.log 2>/dev/null | head -1)
    if [ -f "$EVAL_LOG" ]; then
        RESOLVED=$(grep -a "resolved" "$EVAL_LOG" 2>/dev/null | tail -1 | grep -oP '✓=\K\d+' || echo "?")
        log "Resolved: $RESOLVED"
    fi
}

# Function to upload to HuggingFace
upload_to_hf() {
    log "--- Uploading to HuggingFace ---"
    
    python3 << 'PYEOF' 2>&1 | tee -a "$MONITOR_LOG"
import os
import json
import glob
import shutil
from pathlib import Path
from datetime import datetime

OUTPUT_DIR = os.environ.get('OUTPUT_DIR', '/home/ubuntu/us-east-1-nano-chat-exp/mini-swe-agent/outputs/azure_gpt41mini_verified_20251224_221708')
REPO_NAME = os.environ.get('REPO_NAME', 'mini-swe-agent-azure-gpt41mini-swebench-verified')

try:
    from huggingface_hub import HfApi, login, upload_large_folder
    
    token = os.environ.get('HUGGINGFACE_WRITE_TOKEN')
    if not token:
        print("No HF token found")
        exit(1)
    
    login(token=token)
    api = HfApi()
    user = api.whoami()
    repo_id = f"{user['name']}/{REPO_NAME}"
    
    # Prepare upload directory
    upload_dir = Path("/tmp/hf_upload_monitor")
    if upload_dir.exists():
        shutil.rmtree(upload_dir)
    upload_dir.mkdir()
    
    # Create evaluation folder
    eval_dir = upload_dir / "evaluation"
    eval_dir.mkdir()
    
    # Load and convert preds.json
    with open(f'{OUTPUT_DIR}/preds.json') as f:
        preds = json.load(f)
    
    # Convert to swebench format
    swebench_preds = []
    for inst_id, data in preds.items():
        patch = data.get('model_patch', '')
        if patch and not patch.startswith("Command '"):
            swebench_preds.append({
                "instance_id": inst_id,
                "model_patch": patch,
                "model_name_or_path": "dev-gpt-4.1-mini"
            })
    
    with open(eval_dir / "preds_swebench.json", 'w') as f:
        json.dump(swebench_preds, f, indent=2)
    
    print(f"Prepared {len(swebench_preds)} predictions")
    
    # Copy trajectory folders
    traj_count = 0
    for traj_file in glob.glob(f"{OUTPUT_DIR}/*/*.traj.json"):
        traj_path = Path(traj_file)
        inst_id = traj_path.parent.name
        inst_dir = upload_dir / inst_id
        inst_dir.mkdir(exist_ok=True)
        shutil.copy(traj_file, inst_dir / traj_path.name)
        traj_count += 1
    
    print(f"Prepared {traj_count} trajectories")
    
    # Get evaluation results if available
    eval_logs = glob.glob(f"{OUTPUT_DIR}/evaluation*.log")
    resolved = "?"
    if eval_logs:
        with open(sorted(eval_logs)[-1]) as f:
            content = f.read()
            import re
            matches = re.findall(r'Instances resolved: (\d+)', content)
            if matches:
                resolved = matches[-1]
    
    # Create README
    readme = f'''---
tags:
- code
- swe-bench
- software-engineering
- agent
language:
- en
license: mit
task_categories:
- text-generation
size_categories:
- n<1K
---

# mini-swe-agent Azure GPT-4.1-mini SWE-bench Verified

**Last updated:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}

## Results

| Metric | Value |
|--------|-------|
| **Total Instances** | 500 |
| **Valid Predictions** | {len(swebench_preds)} |
| **Trajectories** | {traj_count} |
| **Resolved** | {resolved} |

## Model Information

| Attribute | Value |
|-----------|-------|
| **Model** | Azure OpenAI GPT-4.1-mini |
| **Agent** | mini-swe-agent v1.17.3 |
| **Workers** | 64 |

## Usage

```python
from huggingface_hub import hf_hub_download

traj = hf_hub_download(
    repo_id="{repo_id}",
    filename="django__django-10999/django__django-10999.traj.json",
    repo_type="dataset"
)
```
'''
    
    with open(upload_dir / "README.md", 'w') as f:
        f.write(readme)
    
    # Upload
    print(f"Uploading to {repo_id}...")
    api.upload_large_folder(
        folder_path=str(upload_dir),
        repo_id=repo_id,
        repo_type="dataset",
    )
    
    print(f"✓ Upload complete: https://huggingface.co/datasets/{repo_id}")
    
except Exception as e:
    print(f"Upload error: {e}")
PYEOF
    
    log "Upload completed"
}

# Main monitoring loop
LAST_UPLOAD=0
ITERATION=0

while true; do
    ITERATION=$((ITERATION + 1))
    CURRENT_TIME=$(date +%s)
    
    log ""
    log "=== Iteration $ITERATION ==="
    
    # Check processes
    check_processes
    
    # Upload if interval passed
    TIME_SINCE_UPLOAD=$((CURRENT_TIME - LAST_UPLOAD))
    if [ $TIME_SINCE_UPLOAD -ge $UPLOAD_INTERVAL ]; then
        export OUTPUT_DIR REPO_NAME
        upload_to_hf
        LAST_UPLOAD=$CURRENT_TIME
    else
        NEXT_UPLOAD=$((UPLOAD_INTERVAL - TIME_SINCE_UPLOAD))
        log "Next upload in ${NEXT_UPLOAD}s"
    fi
    
    # Check if all processes are done
    if ! pgrep -f "swebench.harness.run_evaluation" > /dev/null && \
       ! pgrep -f "minisweagent.*swebench" > /dev/null; then
        log ""
        log "All processes completed!"
        log "Performing final upload..."
        export OUTPUT_DIR REPO_NAME
        upload_to_hf
        log ""
        log "═══════════════════════════════════════════════════════════════════════════"
        log "  MONITORING COMPLETE"
        log "  Final predictions: $(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null)"
        log "═══════════════════════════════════════════════════════════════════════════"
        break
    fi
    
    # Sleep before next check
    sleep 60
done

log "Monitor exiting. Check logs at: $LOG_DIR"
