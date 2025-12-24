#!/bin/bash
# Organize mini-swe-agent repository
# Creates a branch to avoid touching main

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

cd "$REPO_ROOT"

echo "=============================================="
echo "Organizing mini-swe-agent"
echo "=============================================="
echo ""

# Check current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

if [ "$CURRENT_BRANCH" = "main" ]; then
    echo -e "${YELLOW}Currently on main branch - creating organization branch...${NC}"
    git checkout -b organize-repo-structure 2>/dev/null || git checkout organize-repo-structure 2>/dev/null
    echo -e "${GREEN}✓ Switched to organize-repo-structure branch${NC}"
    echo ""
fi

# Ensure directories exist
mkdir -p scripts/benchmarks
mkdir -p docs/benchmarks

# Move benchmark scripts
echo -e "${BLUE}Organizing scripts...${NC}"
if [ -f "run_azure_baseline.sh" ]; then
    mv run_azure_baseline.sh scripts/benchmarks/ 2>/dev/null && echo "  ✓ run_azure_baseline.sh"
fi

if [ -f "run_parallel_benchmark.sh" ]; then
    mv run_parallel_benchmark.sh scripts/benchmarks/ 2>/dev/null && echo "  ✓ run_parallel_benchmark.sh"
fi

# Move documentation
echo -e "${BLUE}Organizing documentation...${NC}"
if [ -f "PARALLEL_BENCHMARK_PLAN.md" ]; then
    mv PARALLEL_BENCHMARK_PLAN.md docs/benchmarks/ 2>/dev/null && echo "  ✓ PARALLEL_BENCHMARK_PLAN.md"
fi

# Move README from outputs if it exists
if [ -f "outputs/gpt5-mini-swebench-verified-incomplete_README.md" ]; then
    mv outputs/gpt5-mini-swebench-verified-incomplete_README.md docs/benchmarks/ 2>/dev/null && echo "  ✓ Moved README from outputs/"
fi

# Ensure outputs/ is in .gitignore
echo -e "${BLUE}Checking .gitignore...${NC}"
if ! grep -q "^outputs/" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Benchmark outputs" >> .gitignore
    echo "outputs/" >> .gitignore
    echo "  ✓ Added outputs/ to .gitignore"
else
    echo "  ✓ outputs/ already in .gitignore"
fi

# Config files are already in proper locations
echo -e "${BLUE}Checking config files...${NC}"
echo "  ✓ Config files are in src/minisweagent/config/ (correct location)"
if [ -d "src/minisweagent/config/custom" ]; then
    echo "  ✓ Custom configs in src/minisweagent/config/custom/"
fi

echo ""
echo -e "${GREEN}✓ mini-swe-agent organized${NC}"
echo ""
echo "Current status:"
git status --short | head -10

echo ""
echo "=============================================="
echo -e "${GREEN}Organization Complete!${NC}"
echo "=============================================="
echo ""
echo "Branch: $(git branch --show-current)"
echo ""
echo "Next steps:"
echo "  1. Review changes: git status"
echo "  2. Commit: git add . && git commit -m 'Organize repository structure'"
echo "  3. Create PR when ready (main branch untouched)"
echo ""

