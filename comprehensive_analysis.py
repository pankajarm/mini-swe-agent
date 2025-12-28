#!/usr/bin/env python3
"""
Comprehensive analysis combining predictions, evaluation results, and trajectory patterns.
"""

import json
import re
import yaml
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi, hf_hub_download


def download_file(repo_id: str, filename: str) -> Path | None:
    """Download a file from HuggingFace."""
    try:
        return Path(hf_hub_download(repo_id=repo_id, filename=filename, repo_type="dataset"))
    except Exception as e:
        return None


def load_evaluation_results(repo_id: str) -> dict[str, str]:
    """Load evaluation results to get exit statuses."""
    api = HfApi()
    files = api.list_repo_files(repo_id=repo_id, repo_type="dataset")
    
    # Try to find the most recent exit_statuses file
    exit_files = [f for f in files if "exit_statuses" in f and f.endswith(".yaml")]
    if exit_files:
        # Get most recent
        exit_file = sorted(exit_files)[-1]
        local_file = download_file(repo_id, exit_file)
        if local_file:
            with open(local_file) as f:
                data = yaml.safe_load(f)
                # Extract exit statuses
                result = {}
                instances_by_status = data.get("instances_by_exit_status", {})
                for status, instances in instances_by_status.items():
                    for instance_id in instances:
                        result[instance_id] = status
                return result
    
    # Try evaluation/final_results.json
    eval_file = download_file(repo_id, "evaluation/final_results.json")
    if eval_file:
        with open(eval_file) as f:
            data = json.load(f)
            result = {}
            # Handle different formats
            if isinstance(data, dict):
                for instance_id, item in data.items():
                    if isinstance(item, dict):
                        result[instance_id] = item.get("exit_status", item.get("status", "Unknown"))
            return result
    
    return {}


def load_predictions(repo_id: str) -> dict[str, Any]:
    """Load predictions."""
    pred_file = download_file(repo_id, "preds.json")
    if not pred_file:
        return {}
    
    with open(pred_file) as f:
        data = json.load(f)
    
    if isinstance(data, list):
        return {item.get("instance_id", ""): item for item in data if item.get("instance_id")}
    elif isinstance(data, dict):
        # Check if keys are instance_ids
        first_key = list(data.keys())[0] if data else ""
        if "__" in first_key:  # Looks like instance_id
            return data
        else:
            # Might be nested
            return {item.get("instance_id", ""): item for item in data.values() if isinstance(item, dict) and item.get("instance_id")}
    
    return {}


def analyze_trajectory_sample(repo_id: str, instance_id: str) -> dict[str, Any]:
    """Analyze a single trajectory file."""
    traj_path = f"{instance_id}/{instance_id}.traj.json"
    traj_file = download_file(repo_id, traj_path)
    
    if not traj_file:
        return {}
    
    try:
        with open(traj_file) as f:
            trajectory = json.load(f)
    except:
        return {}
    
    # Extract commands and analyze
    commands = []
    for step in trajectory:
        if isinstance(step, dict):
            content = step.get("content", "") or step.get("message", "") or ""
            # Extract bash commands
            bash_blocks = re.findall(r"```bash\s*\n(.*?)\n```", content, re.DOTALL)
            commands.extend(bash_blocks)
    
    # Analyze command patterns
    command_types = []
    for cmd in commands:
        first_word = cmd.split()[0] if cmd.split() else ""
        command_types.append(first_word)
    
    counter = Counter(command_types)
    
    # Detect workflow phases
    has_reproduction = any("repro" in cmd.lower() or ("test" in cmd.lower() and "python" in cmd.lower()) for cmd in commands[:10])
    has_editing = any("sed" in cmd or "cat <<" in cmd for cmd in commands)
    has_testing = any("python" in cmd or "pytest" in cmd for cmd in commands)
    
    return {
        "total_commands": len(commands),
        "command_distribution": dict(counter),
        "has_reproduction": has_reproduction,
        "has_editing": has_editing,
        "has_testing": has_testing,
        "sed_count": counter.get("sed", 0),
        "python_count": counter.get("python", 0),
        "grep_count": counter.get("grep", 0),
    }


def main():
    """Main analysis."""
    print("=" * 80)
    print("🔍 Comprehensive Framework Analysis")
    print("=" * 80)
    
    mini_repo = "pankajmathur/mini-swe-agent-azure-gpt41mini-verified"
    gepa_repo = "pankajmathur/gepa-swe-agent-v3.0.1-hybrid-azure-gpt41mini-swebench-verified"
    
    # Load predictions and evaluation results
    print("\n📥 Loading data...")
    mini_preds = load_predictions(mini_repo)
    gepa_preds = load_predictions(gepa_repo)
    mini_exits = load_evaluation_results(mini_repo)
    gepa_exits = load_evaluation_results(gepa_repo)
    
    print(f"   mini-swe-agent: {len(mini_preds)} predictions, {len(mini_exits)} exit statuses")
    print(f"   gepa-swe-agent: {len(gepa_preds)} predictions, {len(gepa_exits)} exit statuses")
    
    # Analyze exit statuses
    mini_submitted = sum(1 for status in mini_exits.values() if status == "Submitted")
    gepa_submitted = sum(1 for status in gepa_exits.values() if status == "Submitted")
    
    print(f"\n✅ Submission Rates:")
    print(f"   mini-swe-agent: {mini_submitted}/{len(mini_exits)} ({mini_submitted/len(mini_exits)*100:.1f}%)" if mini_exits else "   mini-swe-agent: N/A")
    print(f"   gepa-swe-agent: {gepa_submitted}/{len(gepa_exits)} ({gepa_submitted/len(gepa_exits)*100:.1f}%)" if gepa_exits else "   gepa-swe-agent: N/A")
    
    # Analyze trajectory patterns for sample instances
    print(f"\n📊 Analyzing trajectory patterns (sampling 10 instances)...")
    
    mini_sample = list(mini_preds.keys())[:10]
    gepa_sample = list(gepa_preds.keys())[:10]
    
    mini_traj_stats = defaultdict(int)
    gepa_traj_stats = defaultdict(int)
    
    for instance_id in mini_sample:
        stats = analyze_trajectory_sample(mini_repo, instance_id)
        if stats:
            mini_traj_stats["total_commands"] += stats.get("total_commands", 0)
            mini_traj_stats["has_reproduction"] += 1 if stats.get("has_reproduction") else 0
            mini_traj_stats["has_editing"] += 1 if stats.get("has_editing") else 0
            mini_traj_stats["has_testing"] += 1 if stats.get("has_testing") else 0
            mini_traj_stats["sed_count"] += stats.get("sed_count", 0)
            mini_traj_stats["python_count"] += stats.get("python_count", 0)
            mini_traj_stats["analyzed"] += 1
    
    for instance_id in gepa_sample:
        stats = analyze_trajectory_sample(gepa_repo, instance_id)
        if stats:
            gepa_traj_stats["total_commands"] += stats.get("total_commands", 0)
            gepa_traj_stats["has_reproduction"] += 1 if stats.get("has_reproduction") else 0
            gepa_traj_stats["has_editing"] += 1 if stats.get("has_editing") else 0
            gepa_traj_stats["has_testing"] += 1 if stats.get("has_testing") else 0
            gepa_traj_stats["sed_count"] += stats.get("sed_count", 0)
            gepa_traj_stats["python_count"] += stats.get("python_count", 0)
            gepa_traj_stats["analyzed"] += 1
    
    print(f"\n📈 Trajectory Patterns (from samples):")
    if mini_traj_stats["analyzed"] > 0:
        print(f"\n   mini-swe-agent:")
        print(f"      Avg commands per instance: {mini_traj_stats['total_commands'] / mini_traj_stats['analyzed']:.1f}")
        print(f"      Reproduction scripts: {mini_traj_stats['has_reproduction']}/{mini_traj_stats['analyzed']}")
        print(f"      Editing operations: {mini_traj_stats['has_editing']}/{mini_traj_stats['analyzed']}")
        print(f"      Testing operations: {mini_traj_stats['has_testing']}/{mini_traj_stats['analyzed']}")
        print(f"      sed usage: {mini_traj_stats['sed_count']} total")
        print(f"      python usage: {mini_traj_stats['python_count']} total")
    
    if gepa_traj_stats["analyzed"] > 0:
        print(f"\n   gepa-swe-agent:")
        print(f"      Avg commands per instance: {gepa_traj_stats['total_commands'] / gepa_traj_stats['analyzed']:.1f}")
        print(f"      Reproduction scripts: {gepa_traj_stats['has_reproduction']}/{gepa_traj_stats['analyzed']}")
        print(f"      Editing operations: {gepa_traj_stats['has_editing']}/{gepa_traj_stats['analyzed']}")
        print(f"      Testing operations: {gepa_traj_stats['has_testing']}/{gepa_traj_stats['analyzed']}")
        print(f"      sed usage: {gepa_traj_stats['sed_count']} total")
        print(f"      python usage: {gepa_traj_stats['python_count']} total")
    
    # Generate hybrid recommendations
    print(f"\n" + "=" * 80)
    print("🎯 Hybrid Approach Recommendations")
    print("=" * 80)
    
    recommendations = {
        "core_loop": "Use mini-swe-agent's simple, proven loop structure",
        "error_handling": "Combine mini's strict format checking with gepa's reflection on execution errors only",
        "workflow_enforcement": [
            "Require reproduction script creation (mini's strength - {:.0%} do this)".format(
                mini_traj_stats['has_reproduction'] / mini_traj_stats['analyzed'] if mini_traj_stats['analyzed'] > 0 else 0
            ),
            "Test after every edit (mini's strength - {:.0%} do this)".format(
                mini_traj_stats['has_testing'] / mini_traj_stats['analyzed'] if mini_traj_stats['analyzed'] > 0 else 0
            ),
            "Add reflection prompts only on execution errors (gepa's strength)",
        ],
        "prompting": "Use mini's clear, direct prompt with gepa's tool creation guidance for complex cases",
        "limits": {
            "cost": "$3.00 (mini's conservative approach)",
            "steps": "250 (gepa's safety limit)",
        },
    }
    
    print(f"\n1. Core Loop: {recommendations['core_loop']}")
    print(f"\n2. Error Handling: {recommendations['error_handling']}")
    print(f"\n3. Workflow:")
    for item in recommendations['workflow_enforcement']:
        print(f"   - {item}")
    print(f"\n4. Prompting: {recommendations['prompting']}")
    print(f"\n5. Limits: Cost={recommendations['limits']['cost']}, Steps={recommendations['limits']['steps']}")
    
    # Save results
    results = {
        "mini_stats": {
            "total_predictions": len(mini_preds),
            "submitted": mini_submitted,
            "submit_rate": (mini_submitted / len(mini_exits) * 100) if mini_exits else 0,
            "trajectory_patterns": dict(mini_traj_stats),
        },
        "gepa_stats": {
            "total_predictions": len(gepa_preds),
            "submitted": gepa_submitted,
            "submit_rate": (gepa_submitted / len(gepa_exits) * 100) if gepa_exits else 0,
            "trajectory_patterns": dict(gepa_traj_stats),
        },
        "recommendations": recommendations,
    }
    
    output_file = Path("comprehensive_analysis_results.json")
    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n💾 Results saved to: {output_file}")
    print("=" * 80)


if __name__ == "__main__":
    main()

