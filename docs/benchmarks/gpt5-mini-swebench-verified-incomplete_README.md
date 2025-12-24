---
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
pretty_name: GPT-5-mini SWE-bench Verified Trajectories
size_categories:
  - n<1K
---

# GPT-5-mini SWE-bench Verified Trajectories

This dataset contains agent trajectories from running **GPT-5-mini** on the [SWE-bench Verified](https://www.swebench.com/) benchmark.

## Model Information

| Attribute | Value |
|-----------|-------|
| **Model** | GPT-5-mini |
| **Parameters** | GPT-5-mini (2025-08-07) |
| **Framework** | mini-swe-agent (standard) |
| **Status** | Incomplete (78/500 tasks) |
| **Provider** | OpenAI |
| **Reasoning Effort** | High |

## Benchmark Results

| Metric | Value |
|--------|-------|
| **Total Instances** | 500 |
| **Submitted** | 78 (15.6%) |
| **Resolved** | **0 (0.0%)** |

## Usage

```python
from huggingface_hub import hf_hub_download, list_repo_files

# List all files
files = list_repo_files("pankajmathur/gpt5-mini-swebench-verified-incomplete", repo_type="dataset")

# Download a specific trajectory
traj = hf_hub_download(
    repo_id="pankajmathur/gpt5-mini-swebench-verified-incomplete",
    filename="astropy__astropy-12907/astropy__astropy-12907.traj.json",
    repo_type="dataset"
)
```

## Citation

```bibtex
@misc{gpt-5-mini-swebench-2024,
  author = {Pankaj Mathur},
  title = {GPT-5-mini SWE-bench Verified Trajectories},
  year = {2024},
  publisher = {Hugging Face},
  url = {https://huggingface.co/datasets/pankajmathur/gpt5-mini-swebench-verified-incomplete}
}
```

## Related

- [SWE-bench](https://www.swebench.com/)
- [mini-swe-agent](https://github.com/pankajarm/mini-swe-agent)
