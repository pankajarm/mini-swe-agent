# mini-swe-agent Repository Organization

**Date:** 2025-12-24  
**Branch:** `organize-repo-structure` (main branch untouched)

## Overview

Organized repository structure following GitHub best practices while preserving the main branch of this public repository.

## Changes Made

### Scripts Organization
- **Benchmark scripts** → `scripts/benchmarks/`
  - `run_azure_baseline.sh`
  - `run_parallel_benchmark.sh`

### Documentation Organization
- **Benchmark documentation** → `docs/benchmarks/`
  - `PARALLEL_BENCHMARK_PLAN.md`
  - `gpt5-mini-swebench-verified-incomplete_README.md` (moved from outputs/)

### Configuration Files
- Config files remain in proper locations:
  - `src/minisweagent/config/azure_gpt41_mini.yaml`
  - `src/minisweagent/config/custom/gpt5_mini_live.yaml`
  - `src/minisweagent/config/extra/swebench_gpt5_mini.yaml`

### .gitignore Updates
- Added `outputs/` to `.gitignore` to ensure benchmark outputs remain untracked

## Directory Structure

```
mini-swe-agent/
├── scripts/
│   └── benchmarks/     # Benchmark execution scripts
├── docs/
│   └── benchmarks/    # Benchmark documentation
├── src/
│   └── minisweagent/
│       └── config/
│           ├── azure_gpt41_mini.yaml
│           ├── custom/          # Custom configs
│           └── extra/           # Extra configs
└── outputs/           # Untracked (benchmark outputs)
```

## Verification

✅ Main branch untouched  
✅ All scripts organized  
✅ Documentation organized  
✅ Config files in correct locations  
✅ `outputs/` properly ignored  

## Next Steps

1. Review changes: `git status`
2. Commit: `git add . && git commit -m 'Organize repository structure'`
3. Create PR to main when ready (with minimal changes)

## Running Scripts After Reorganization

```bash
# Benchmark scripts
./scripts/benchmarks/run_azure_baseline.sh
./scripts/benchmarks/run_parallel_benchmark.sh
```

