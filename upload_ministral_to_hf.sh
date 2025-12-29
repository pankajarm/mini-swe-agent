#!/bin/bash
# =============================================================================
# Upload Ministral3-3B-SFT Trajectories to Hugging Face Dataset
# Runs in screen session for safe disconnection
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="${1:-}"
REPO_ID="${2:-pankajmathur/ministral3-3b-sft-swebench-verified-traj}"
EVAL_DIR="${3:-}"
SCREEN_NAME="ministral3_upload"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Upload Ministral3-3B-SFT Trajectories to Hugging Face${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Auto-detect output directory if not provided
if [ -z "$OUTPUT_DIR" ]; then
    LATEST_OUTPUT=$(ls -td "$SCRIPT_DIR/outputs/ministral3_"* 2>/dev/null | head -1)
    if [ -n "$LATEST_OUTPUT" ]; then
        OUTPUT_DIR="$LATEST_OUTPUT"
        echo -e "${YELLOW}Auto-detected output directory: $OUTPUT_DIR${NC}"
    else
        echo -e "${RED}[ERROR] Output directory not found${NC}"
        echo ""
        echo "Usage: $0 [output_dir] [repo_id] [eval_dir]"
        echo ""
        echo "Or place output directory in outputs/ministral3_*"
        exit 1
    fi
fi

if [ ! -d "$OUTPUT_DIR" ]; then
    echo -e "${RED}[ERROR] Output directory not found: $OUTPUT_DIR${NC}"
    exit 1
fi

# Auto-detect eval directory if not provided
if [ -z "$EVAL_DIR" ]; then
    EVAL_DIRS=$(find "$OUTPUT_DIR" -type d -name "evaluation_*" 2>/dev/null | head -1)
    if [ -n "$EVAL_DIRS" ]; then
        EVAL_DIR="$EVAL_DIRS"
        echo -e "${YELLOW}Auto-detected eval directory: $EVAL_DIR${NC}"
    fi
fi

# Check if screen session already exists
if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${YELLOW}[WARN] Screen session '$SCREEN_NAME' already exists${NC}"
    echo ""
    echo "Attach with: screen -r $SCREEN_NAME"
    echo "Kill with: screen -S $SCREEN_NAME -X quit"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Output Dir:   $OUTPUT_DIR"
echo "  Repo ID:      $REPO_ID"
if [ -n "$EVAL_DIR" ]; then
    echo "  Eval Dir:     $EVAL_DIR"
fi
echo "  Screen:       $SCREEN_NAME"
echo ""

# Check for required files
if [ ! -f "$OUTPUT_DIR/preds.json" ]; then
    echo -e "${RED}[ERROR] preds.json not found in $OUTPUT_DIR${NC}"
    exit 1
fi

# Count predictions and get evaluation results if available
PRED_COUNT=$(python3 -c "import json; print(len(json.load(open('$OUTPUT_DIR/preds.json'))))" 2>/dev/null || echo "0")
RESOLVED=0
TOTAL=500

if [ -n "$EVAL_DIR" ] && [ -f "$EVAL_DIR/final_summary.json" ]; then
    RESOLVED=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('resolved', 0))" 2>/dev/null || echo "0")
    TOTAL=$(python3 -c "import json; print(json.load(open('$EVAL_DIR/final_summary.json')).get('total', $PRED_COUNT))" 2>/dev/null || echo "$PRED_COUNT")
fi

echo "  Predictions:  $PRED_COUNT instances"
if [ "$RESOLVED" -gt 0 ]; then
    echo "  Resolved:     $RESOLVED / $TOTAL ($(echo "scale=1; $RESOLVED * 100 / $TOTAL" | bc)%)"
fi
echo ""

# Check for HuggingFace token
HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_TOKEN:-}}"
if [ -z "$HF_TOKEN" ]; then
    # Try to load from .env file
    PARENT_ENV="/home/ubuntu/us-east-1-nano-chat-exp/swe-bench-huggingface-models/.env"
    if [ -f "$PARENT_ENV" ]; then
        set -a
        source "$PARENT_ENV"
        set +a
        HF_TOKEN="${HF_TOKEN:-${HUGGINGFACE_TOKEN:-}}"
    fi
fi

if [ -z "$HF_TOKEN" ]; then
    echo -e "${YELLOW}[WARN] HuggingFace token not found in environment${NC}"
    echo ""
    echo "Please set HF_TOKEN or HUGGINGFACE_TOKEN environment variable"
    echo "Or add it to .env file"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create upload script
UPLOAD_SCRIPT="$SCRIPT_DIR/logs/upload_ministral_wrapper.sh"
LOG_FILE="$SCRIPT_DIR/logs/upload_ministral_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$(dirname "$LOG_FILE")"

cat > "$UPLOAD_SCRIPT" << EOFWRAP
#!/bin/bash
# Upload Wrapper (runs in screen session)

cd "$SCRIPT_DIR"

export HF_TOKEN="$HF_TOKEN"
export HUGGINGFACE_TOKEN="$HF_TOKEN"

echo "=============================================="
echo "  Upload to Hugging Face Dataset"
echo "  Started: \$(date)"
echo "=============================================="
echo ""
echo "  Repo: $REPO_ID"
echo "  Source: $OUTPUT_DIR"
echo ""

python3 << 'EOFUPLOAD'
import json
import sys
from pathlib import Path
from huggingface_hub import HfApi, create_repo
import os

# Configuration
repo_id = "$REPO_ID"
output_dir = Path("$OUTPUT_DIR")
eval_dir = Path("$EVAL_DIR") if "$EVAL_DIR" else None
hf_token = os.getenv("HF_TOKEN") or os.getenv("HUGGINGFACE_TOKEN")

if not hf_token:
    print("❌ ERROR: HuggingFace token not found")
    sys.exit(1)

api = HfApi(token=hf_token)

# Create repo
print(f"\n📦 Creating/verifying repository: {repo_id}")
try:
    create_repo(repo_id, repo_type="dataset", token=hf_token, exist_ok=True)
    print(f"✅ Repository ready: https://huggingface.co/datasets/{repo_id}")
except Exception as e:
    print(f"⚠️  Repo creation note: {e}")

# Prepare trajectories directory structure
traj_dir = output_dir / "trajectories"
traj_dir.mkdir(exist_ok=True)

# Find all trajectory files (*.traj.json)
traj_files = list(output_dir.glob("**/*.traj.json"))
if not traj_files:
    print("⚠️  No trajectory files found (*.traj.json)")
    print(f"   Searching in: {output_dir}")
else:
    print(f"\n📁 Found {len(traj_files)} trajectory files")
    
    # Organize trajectories by instance (create directory structure)
    for traj_file in traj_files:
        # Extract instance ID from filename (e.g., astropy__astropy-12907.traj.json)
        instance_id = traj_file.stem.replace(".traj", "")
        instance_dir = traj_dir / instance_id
        instance_dir.mkdir(exist_ok=True)
        
        # Copy trajectory file
        dest_file = instance_dir / traj_file.name
        if not dest_file.exists():
            import shutil
            shutil.copy2(traj_file, dest_file)
    
    staged_count = len(list(traj_dir.glob("*/*.traj.json")))
    print(f"✅ Organized {staged_count} trajectory files")

# Upload trajectories using upload_large_folder (resumable)
print(f"\n📤 Uploading trajectories using upload_large_folder...")
print("   (This is resumable - you can interrupt and restart anytime)")
print(f"   Progress saved to: {traj_dir}/.cache/.huggingface/\n")

try:
    api.upload_large_folder(
        repo_id=repo_id,
        folder_path=str(traj_dir),
        repo_type="dataset",
        num_workers=4,
        print_report=True,
        print_report_every=30,
    )
    print("✅ Trajectories uploaded")
except Exception as e:
    print(f"❌ Error uploading trajectories: {e}")
    sys.exit(1)

# Upload preds.json
print(f"\n📤 Uploading predictions file...")
try:
    api.upload_file(
        path_or_fileobj=str(output_dir / "preds.json"),
        path_in_repo="preds.json",
        repo_id=repo_id,
        repo_type="dataset",
    )
    print("✅ Predictions file uploaded")
except Exception as e:
    print(f"⚠️  Error uploading preds.json: {e}")

# Upload evaluation results if available
if eval_dir and eval_dir.exists():
    print(f"\n📤 Uploading evaluation files...")
    eval_files = [
        "final_summary.json",
        "eval.log",
    ]
    
    for fname in eval_files:
        fpath = eval_dir / fname
        if fpath.exists():
            try:
                api.upload_file(
                    path_or_fileobj=str(fpath),
                    path_in_repo=f"evaluation/{fname}",
                    repo_id=repo_id,
                    repo_type="dataset",
                )
                print(f"✅ Uploaded: {fname}")
            except Exception as e:
                print(f"⚠️  Error uploading {fname}: {e}")
    
    # Upload result JSON file if exists
    result_files = list(eval_dir.glob("*.json"))
    for result_file in result_files:
        if result_file.name not in ["final_summary.json"]:
            try:
                api.upload_file(
                    path_or_fileobj=str(result_file),
                    path_in_repo=f"evaluation/{result_file.name}",
                    repo_id=repo_id,
                    repo_type="dataset",
                )
                print(f"✅ Uploaded: {result_file.name}")
            except Exception as e:
                print(f"⚠️  Error uploading {result_file.name}: {e}")

# Generate and upload README
print(f"\n📝 Generating README...")

# Load evaluation summary if available
resolved = 0
total = 500
submitted = len(traj_files) if traj_files else 0

if eval_dir and (eval_dir / "final_summary.json").exists():
    with open(eval_dir / "final_summary.json") as f:
        summary = json.load(f)
        resolved = summary.get("resolved", 0)
        total = summary.get("total", submitted)
        submitted = summary.get("total", submitted)

readme_content = f"""---
license: mit
task_categories:
  - text-generation
language:
  - en
tags:
  - code
  - swe-bench
  - software-engineering
  - agent
pretty_name: Ministral3-3B-SFT SWE-bench Verified Trajectories
size_categories:
  - n<1K
---

# Ministral3-3B-SFT SWE-bench Verified Trajectories

This dataset contains agent trajectories from running **Ministral3-3B-SFT** on the [SWE-bench Verified](https://www.swebench.com/) benchmark.

## Model Information

| Attribute | Value |
|-----------|-------|
| **Model** | Ministral3-3B-SFT |
| **Parameters** | 3.9B (3B base + multimodal components) |
| **Provider** | Local vLLM |

## Benchmark Results

| Metric | Value |
|--------|-------|
| **Total Instances** | {total} |
| **Submitted** | {submitted} ({submitted/total*100:.1f}%) |
| **Resolved** | **{resolved} ({resolved/total*100:.1f}%)** |

## Usage

\`\`\`python
from huggingface_hub import hf_hub_download, list_repo_files

# List all files
files = list_repo_files("{repo_id}", repo_type="dataset")

# Download a specific trajectory
traj = hf_hub_download(
    repo_id="{repo_id}",
    filename="astropy__astropy-12907/astropy__astropy-12907.traj.json",
    repo_type="dataset"
)
\`\`\`

## Citation

\`\`\`bibtex
@misc{{ministral3-3b-sft-swebench-2024,
  author = {{Pankaj Mathur}},
  title = {{Ministral3-3B-SFT SWE-bench Verified Trajectories}},
  year = {{2024}},
  publisher = {{Hugging Face}},
  url = {{https://huggingface.co/datasets/{repo_id}}}
}}
\`\`\`

## Related

- [SWE-bench](https://www.swebench.com/)
- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)
"""

try:
    readme_path = Path("/tmp/README_ministral3.md")
    readme_path.write_text(readme_content)
    
    api.upload_file(
        path_or_fileobj=str(readme_path),
        path_in_repo="README.md",
        repo_id=repo_id,
        repo_type="dataset",
    )
    print("✅ README uploaded")
except Exception as e:
    print(f"⚠️  Error uploading README: {e}")

print(f"\n✅ Done! Dataset: https://huggingface.co/datasets/{repo_id}")
EOFUPLOAD

echo ""
echo "=============================================="
echo "  Upload completed"
echo "  End time: \$(date)"
echo "=============================================="
EOFWRAP

chmod +x "$UPLOAD_SCRIPT"

# Launch in screen session
echo -e "${BLUE}Launching upload in screen session '$SCREEN_NAME'...${NC}"
screen -dmS "$SCREEN_NAME" bash "$UPLOAD_SCRIPT" 2>&1 | tee "$LOG_FILE"
sleep 2

if screen -list 2>/dev/null | grep -q "$SCREEN_NAME"; then
    echo -e "${GREEN}✓ Screen session '$SCREEN_NAME' started${NC}"
    echo ""
    echo "  screen -r $SCREEN_NAME"
    echo "  tail -f $LOG_FILE"
    echo ""
    echo -e "${GREEN}Safe to disconnect.${NC}"
else
    echo -e "${RED}Failed to start screen session${NC}"
    exit 1
fi

