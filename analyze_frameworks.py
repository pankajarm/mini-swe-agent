#!/usr/bin/env python3
"""
Comprehensive analysis of mini-swe-agent vs gepa-swe-agent frameworks.
Downloads datasets, analyzes trajectories, and identifies hybrid opportunities.
"""

import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from datasets import load_dataset
from huggingface_hub import HfApi, hf_hub_download
import json


def load_trajectory_data(dataset_name: str) -> dict[str, Any]:
    """Load dataset from HuggingFace and extract trajectory data."""
    print(f"📥 Loading dataset: {dataset_name}")
    
    # Try loading with streaming to handle malformed files
    try:
        dataset = load_dataset(dataset_name, split="test", streaming=False, verification_mode="no_checks")
    except Exception as e:
        print(f"   ⚠️  Error loading with standard method: {e}")
        print(f"   Trying streaming mode...")
        try:
            dataset = load_dataset(dataset_name, split="test", streaming=True)
        except Exception as e2:
            print(f"   ❌ Failed to load dataset: {e2}")
            # Try loading just predictions
            return load_predictions_only(dataset_name)
    
    data = {}
    loaded_count = 0
    error_count = 0
    
    for item in dataset:
        try:
            instance_id = item.get("instance_id", "")
            if not instance_id:
                continue
            
            # Extract trajectory if available
            trajectory = item.get("trajectory", [])
            prediction = item.get("prediction", "")
            test_patch = item.get("test_patch", "")
            exit_status = item.get("exit_status", "")
            
            data[instance_id] = {
                "trajectory": trajectory,
                "prediction": prediction,
                "test_patch": test_patch,
                "exit_status": exit_status,
                "metadata": {k: v for k, v in item.items() if k not in ["trajectory", "prediction", "test_patch", "exit_status", "instance_id"]}
            }
            loaded_count += 1
        except Exception as e:
            error_count += 1
            if error_count <= 5:
                print(f"   ⚠️  Error loading item: {e}")
    
    print(f"   Loaded {loaded_count} instances (errors: {error_count})")
    return data


def load_predictions_only(dataset_name: str) -> dict[str, Any]:
    """Fallback: Load only predictions if trajectory loading fails."""
    print(f"   📥 Loading predictions only (fallback mode)...")
    try:
        api = HfApi()
        repo_id = dataset_name
        
        # List files in the repo
        files = api.list_repo_files(repo_id=repo_id, repo_type="dataset")
        print(f"   Found {len(files)} files in repo")
        
        # Try to find predictions or eval files
        pred_files = [f for f in files if "prediction" in f.lower() or "eval" in f.lower() or f.endswith(".jsonl")]
        
        data = {}
        for pred_file in pred_files[:3]:  # Try first 3 matching files
            try:
                print(f"   Trying: {pred_file}")
                local_file = hf_hub_download(repo_id=repo_id, filename=pred_file, repo_type="dataset")
                
                with open(local_file) as f:
                    if pred_file.endswith(".jsonl"):
                        # JSONL format
                        for line in f:
                            if line.strip():
                                item = json.loads(line)
                                instance_id = item.get("instance_id", "")
                                if instance_id:
                                    data[instance_id] = {
                                        "prediction": item.get("prediction", ""),
                                        "test_patch": item.get("test_patch", ""),
                                        "exit_status": item.get("exit_status", ""),
                                        "trajectory": [],
                                    }
                    else:
                        # JSON format
                        content = json.load(f)
                        if isinstance(content, list):
                            for item in content:
                                instance_id = item.get("instance_id", "")
                                if instance_id:
                                    data[instance_id] = {
                                        "prediction": item.get("prediction", ""),
                                        "test_patch": item.get("test_patch", ""),
                                        "exit_status": item.get("exit_status", ""),
                                        "trajectory": [],
                                    }
                        elif isinstance(content, dict):
                            # Might be a dict with instance_id as keys
                            for instance_id, item in content.items():
                                if isinstance(item, dict):
                                    data[instance_id] = {
                                        "prediction": item.get("prediction", ""),
                                        "test_patch": item.get("test_patch", ""),
                                        "exit_status": item.get("exit_status", ""),
                                        "trajectory": [],
                                    }
                
                if data:
                    print(f"   ✅ Loaded {len(data)} instances from {pred_file}")
                    break
            except Exception as e:
                print(f"   ⚠️  Error loading {pred_file}: {e}")
                continue
        
        return data
    except Exception as e:
        print(f"   ❌ Could not load predictions: {e}")
        return {}


def extract_commands(trajectory: list) -> list[str]:
    """Extract all commands from a trajectory."""
    commands = []
    for step in trajectory:
        if isinstance(step, dict):
            # Check various possible formats
            content = step.get("content", "")
            action = step.get("action", "")
            message = step.get("message", "")
            
            # Try to extract bash commands
            text = content or action or message or str(step)
            
            # Look for bash code blocks
            bash_blocks = re.findall(r"```bash\s*\n(.*?)\n```", text, re.DOTALL)
            if bash_blocks:
                commands.extend(bash_blocks)
            elif action:
                commands.append(action)
            elif "```" in text:
                # Try to extract any code block
                code_blocks = re.findall(r"```\w*\s*\n(.*?)\n```", text, re.DOTALL)
                commands.extend(code_blocks)
    
    return [cmd.strip() for cmd in commands if cmd.strip()]


def analyze_command_patterns(commands: list[str]) -> dict[str, Any]:
    """Analyze command usage patterns."""
    if not commands:
        return {}
    
    # Extract command types
    command_types = []
    for cmd in commands:
        # Get first word (command)
        first_word = cmd.split()[0] if cmd.split() else ""
        command_types.append(first_word)
    
    counter = Counter(command_types)
    total = len(commands)
    
    # Calculate percentages
    percentages = {cmd: (count / total) * 100 for cmd, count in counter.items()}
    
    # Identify key patterns
    patterns = {
        "editing": sum(counter.get(cmd, 0) for cmd in ["sed", "cat", "tee", "echo"]),
        "testing": sum(counter.get(cmd, 0) for cmd in ["python", "pytest", "test"]),
        "searching": sum(counter.get(cmd, 0) for cmd in ["grep", "find", "ls"]),
        "reading": sum(counter.get(cmd, 0) for cmd in ["cat", "head", "tail", "less"]),
    }
    
    return {
        "total_commands": total,
        "command_distribution": dict(counter),
        "command_percentages": percentages,
        "pattern_counts": patterns,
        "pattern_percentages": {k: (v / total) * 100 for k, v in patterns.items()},
    }


def analyze_workflow_steps(trajectory: list) -> dict[str, Any]:
    """Analyze workflow steps and patterns."""
    commands = extract_commands(trajectory)
    
    # Detect workflow phases
    phases = {
        "exploration": 0,
        "reproduction": 0,
        "editing": 0,
        "testing": 0,
        "submission": 0,
    }
    
    for i, cmd in enumerate(commands):
        cmd_lower = cmd.lower()
        
        # Exploration phase
        if any(x in cmd_lower for x in ["grep", "find", "ls", "cat", "head", "tail"]):
            phases["exploration"] += 1
        
        # Reproduction phase
        if any(x in cmd_lower for x in ["repro", "test", "python", "pytest"]) and "test" in cmd_lower[:50]:
            phases["reproduction"] += 1
        
        # Editing phase
        if any(x in cmd_lower for x in ["sed -i", "cat <<", "tee", "echo >"]):
            phases["editing"] += 1
        
        # Testing phase
        if any(x in cmd_lower for x in ["python", "pytest", "test"]) and i > 0:
            phases["testing"] += 1
        
        # Submission phase
        if any(x in cmd_lower for x in ["submit", "complete_task", "gepa_submit", "git add", "git diff"]):
            phases["submission"] += 1
    
    return {
        "total_steps": len(commands),
        "phases": phases,
        "has_reproduction": phases["reproduction"] > 0,
        "has_testing": phases["testing"] > 0,
        "has_editing": phases["editing"] > 0,
    }


def analyze_error_handling(trajectory: list) -> dict[str, Any]:
    """Analyze error handling and recovery patterns."""
    error_recovery_count = 0
    format_errors = 0
    execution_errors = 0
    
    for step in trajectory:
        if isinstance(step, dict):
            content = str(step.get("content", "")) + str(step.get("message", ""))
            content_lower = content.lower()
            
            # Detect error recovery
            if any(x in content_lower for x in ["error", "failed", "exception", "traceback"]):
                error_recovery_count += 1
            
            # Detect format errors
            if "format" in content_lower and "error" in content_lower:
                format_errors += 1
            
            # Detect execution errors
            if "returncode" in str(step) and step.get("returncode", 0) != 0:
                execution_errors += 1
    
    return {
        "error_recovery_count": error_recovery_count,
        "format_errors": format_errors,
        "execution_errors": execution_errors,
    }


def compare_frameworks(mini_data: dict, gepa_data: dict) -> dict[str, Any]:
    """Compare both frameworks comprehensively."""
    
    # Find common instances
    mini_instances = set(mini_data.keys())
    gepa_instances = set(gepa_data.keys())
    common_instances = mini_instances & gepa_instances
    mini_only = mini_instances - gepa_instances
    gepa_only = gepa_instances - mini_instances
    
    print(f"\n📊 Dataset Comparison:")
    print(f"   mini-swe-agent: {len(mini_instances)} instances")
    print(f"   gepa-swe-agent: {len(gepa_instances)} instances")
    print(f"   Common: {len(common_instances)} instances")
    print(f"   mini-only: {len(mini_only)} instances")
    print(f"   gepa-only: {len(gepa_only)} instances")
    
    # Analyze exit statuses
    mini_submitted = sum(1 for k, v in mini_data.items() if v.get("exit_status") == "Submitted")
    gepa_submitted = sum(1 for k, v in gepa_data.items() if v.get("exit_status") == "Submitted")
    
    # Analyze trajectories for common instances
    comparison_results = {
        "mini_only": list(mini_only),
        "gepa_only": list(gepa_only),
        "common_instances": list(common_instances),
        "mini_submitted": mini_submitted,
        "gepa_submitted": gepa_submitted,
        "mini_submit_rate": (mini_submitted / len(mini_instances) * 100) if mini_instances else 0,
        "gepa_submit_rate": (gepa_submitted / len(gepa_instances) * 100) if gepa_instances else 0,
    }
    
    # Detailed analysis for common instances
    mini_stats = defaultdict(lambda: {"count": 0, "total": 0})
    gepa_stats = defaultdict(lambda: {"count": 0, "total": 0})
    
    for instance_id in list(common_instances)[:100]:  # Sample first 100 for detailed analysis
        mini_item = mini_data[instance_id]
        gepa_item = gepa_data[instance_id]
        
        # Analyze mini
        mini_commands = extract_commands(mini_item.get("trajectory", []))
        mini_cmd_stats = analyze_command_patterns(mini_commands)
        mini_workflow = analyze_workflow_steps(mini_item.get("trajectory", []))
        mini_errors = analyze_error_handling(mini_item.get("trajectory", []))
        
        # Analyze gepa
        gepa_commands = extract_commands(gepa_item.get("trajectory", []))
        gepa_cmd_stats = analyze_command_patterns(gepa_commands)
        gepa_workflow = analyze_workflow_steps(gepa_item.get("trajectory", []))
        gepa_errors = analyze_error_handling(gepa_item.get("trajectory", []))
        
        # Aggregate stats
        for key, value in mini_cmd_stats.get("pattern_percentages", {}).items():
            mini_stats[f"pattern_{key}"]["count"] += value
            mini_stats[f"pattern_{key}"]["total"] += 1
        
        for key, value in gepa_cmd_stats.get("pattern_percentages", {}).items():
            gepa_stats[f"pattern_{key}"]["count"] += value
            gepa_stats[f"pattern_{key}"]["total"] += 1
        
        mini_stats["has_reproduction"]["count"] += 1 if mini_workflow.get("has_reproduction") else 0
        mini_stats["has_reproduction"]["total"] += 1
        gepa_stats["has_reproduction"]["count"] += 1 if gepa_workflow.get("has_reproduction") else 0
        gepa_stats["has_reproduction"]["total"] += 1
        
        mini_stats["avg_steps"]["count"] += mini_workflow.get("total_steps", 0)
        mini_stats["avg_steps"]["total"] += 1
        gepa_stats["avg_steps"]["count"] += gepa_workflow.get("total_steps", 0)
        gepa_stats["avg_steps"]["total"] += 1
    
    # Calculate averages
    comparison_results["mini_averages"] = {
        k: v["count"] / v["total"] if v["total"] > 0 else 0
        for k, v in mini_stats.items()
    }
    comparison_results["gepa_averages"] = {
        k: v["count"] / v["total"] if v["total"] > 0 else 0
        for k, v in gepa_stats.items()
    }
    
    return comparison_results


def identify_strengths(mini_data: dict, gepa_data: dict, comparison: dict) -> dict[str, Any]:
    """Identify strengths of each framework."""
    
    strengths = {
        "mini_swe_agent": [],
        "gepa_swe_agent": [],
    }
    
    # Analyze which instances each solved
    mini_solved = {k for k, v in mini_data.items() if v.get("exit_status") == "Submitted"}
    gepa_solved = {k for k, v in gepa_data.items() if v.get("exit_status") == "Submitted"}
    
    mini_only_solved = mini_solved - gepa_solved
    gepa_only_solved = gepa_solved - mini_solved
    both_solved = mini_solved & gepa_solved
    
    # Analyze mini strengths
    if comparison["mini_averages"].get("has_reproduction", 0) > 0.5:
        strengths["mini_swe_agent"].append("Strong reproduction script creation")
    
    if comparison["mini_averages"].get("pattern_testing", 0) > 15:
        strengths["mini_swe_agent"].append("Heavy testing and verification")
    
    if comparison["mini_averages"].get("pattern_editing", 0) > 30:
        strengths["mini_swe_agent"].append("Focused editing approach")
    
    # Analyze gepa strengths
    if comparison["gepa_averages"].get("has_reproduction", 0) > 0.3:
        strengths["gepa_swe_agent"].append("Reproduction capability")
    
    # Check for reflection usage
    gepa_reflections = 0
    for instance_id, item in list(gepa_data.items())[:100]:
        trajectory = item.get("trajectory", [])
        for step in trajectory:
            if isinstance(step, dict):
                content = str(step.get("content", ""))
                if "reflection" in content.lower():
                    gepa_reflections += 1
                    break
    
    if gepa_reflections > 10:
        strengths["gepa_swe_agent"].append("Reflective error handling")
    
    strengths["mini_only_solved"] = list(mini_only_solved)[:20]
    strengths["gepa_only_solved"] = list(gepa_only_solved)[:20]
    strengths["both_solved"] = len(both_solved)
    
    return strengths


def generate_hybrid_recommendations(comparison: dict, strengths: dict) -> dict[str, Any]:
    """Generate recommendations for a hybrid approach."""
    
    recommendations = {
        "core_loop": "Use mini-swe-agent's simple loop structure",
        "error_handling": "Combine mini's strict format checking with gepa's reflection on execution errors",
        "workflow": [
            "Require reproduction script creation (mini strength)",
            "Test after every edit (mini strength)",
            "Add reflection prompts only on execution errors (gepa strength)",
            "Use first-block fallback sparingly (gepa feature, but be careful)",
        ],
        "prompting": [
            "Use mini's clear, direct prompt structure",
            "Add gepa's tool creation guidance for complex cases",
            "Emphasize testing workflow from mini",
        ],
        "limits": "Use mini's cost limit ($3) but gepa's step limit (250) for safety",
    }
    
    return recommendations


def main():
    """Main analysis function."""
    print("=" * 80)
    print("🔍 Comprehensive Framework Analysis: mini-swe-agent vs gepa-swe-agent")
    print("=" * 80)
    
    # Load datasets
    mini_dataset = "pankajmathur/mini-swe-agent-azure-gpt41mini-verified"
    gepa_dataset = "pankajmathur/gepa-swe-agent-v3.0.1-hybrid-azure-gpt41mini-swebench-verified"
    
    mini_data = load_trajectory_data(mini_dataset)
    gepa_data = load_trajectory_data(gepa_dataset)
    
    # Compare frameworks
    print("\n" + "=" * 80)
    print("📊 Comparing Frameworks")
    print("=" * 80)
    comparison = compare_frameworks(mini_data, gepa_data)
    
    # Identify strengths
    print("\n" + "=" * 80)
    print("💪 Identifying Strengths")
    print("=" * 80)
    strengths = identify_strengths(mini_data, gepa_data, comparison)
    
    # Generate recommendations
    print("\n" + "=" * 80)
    print("🎯 Hybrid Recommendations")
    print("=" * 80)
    recommendations = generate_hybrid_recommendations(comparison, strengths)
    
    # Print summary
    print("\n" + "=" * 80)
    print("📋 Summary")
    print("=" * 80)
    print(f"\n✅ mini-swe-agent submitted: {comparison['mini_submitted']} ({comparison['mini_submit_rate']:.1f}%)")
    print(f"✅ gepa-swe-agent submitted: {comparison['gepa_submitted']} ({comparison['gepa_submit_rate']:.1f}%)")
    
    print(f"\n💪 mini-swe-agent strengths:")
    for strength in strengths["mini_swe_agent"]:
        print(f"   - {strength}")
    
    print(f"\n💪 gepa-swe-agent strengths:")
    for strength in strengths["gepa_swe_agent"]:
        print(f"   - {strength}")
    
    print(f"\n🎯 Hybrid Recommendations:")
    print(f"   Core Loop: {recommendations['core_loop']}")
    print(f"   Error Handling: {recommendations['error_handling']}")
    print(f"   Workflow:")
    for item in recommendations['workflow']:
        print(f"     - {item}")
    
    # Save detailed results
    output_file = Path("framework_analysis_results.json")
    results = {
        "comparison": comparison,
        "strengths": strengths,
        "recommendations": recommendations,
    }
    
    with open(output_file, "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n💾 Detailed results saved to: {output_file}")
    print("=" * 80)


if __name__ == "__main__":
    main()

