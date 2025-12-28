#!/usr/bin/env python3
"""
Comprehensive analysis of mini-swe-agent vs gepa-swe-agent frameworks.
Downloads and analyzes predictions, results, and trajectories.
"""

import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from huggingface_hub import HfApi, hf_hub_download


def download_and_load_json(repo_id: str, filename: str) -> Any:
    """Download and load a JSON file from HuggingFace."""
    try:
        local_file = hf_hub_download(repo_id=repo_id, filename=filename, repo_type="dataset")
        with open(local_file) as f:
            return json.load(f)
    except Exception as e:
        print(f"   ⚠️  Error loading {filename}: {e}")
        return None


def load_predictions(repo_id: str) -> dict[str, Any]:
    """Load predictions from a dataset."""
    print(f"📥 Loading predictions from {repo_id}")
    
    # Try different possible filenames
    for filename in ["preds.json", "predictions.json", "results.json"]:
        data = download_and_load_json(repo_id, filename)
        if data:
            print(f"   ✅ Loaded {filename}")
            
            # Handle different formats
            if isinstance(data, list):
                # List of items
                result = {}
                for item in data:
                    instance_id = item.get("instance_id", "")
                    if instance_id:
                        result[instance_id] = item
                return result
            elif isinstance(data, dict):
                # Check if it's a dict with instance_id as keys or nested structure
                if "instance_id" in str(data.values())[:100]:  # Quick check
                    # Might be list-like structure
                    return data
                else:
                    # Try to find predictions nested
                    for key in ["predictions", "results", "data"]:
                        if key in data:
                            items = data[key]
                            if isinstance(items, list):
                                result = {}
                                for item in items:
                                    instance_id = item.get("instance_id", "")
                                    if instance_id:
                                        result[instance_id] = item
                                return result
                    # Return as-is, might be keyed by instance_id
                    return data
    
    return {}


def extract_commands_from_text(text: str) -> list[str]:
    """Extract bash commands from text."""
    commands = []
    
    # Look for bash code blocks
    bash_blocks = re.findall(r"```bash\s*\n(.*?)\n```", text, re.DOTALL)
    commands.extend(bash_blocks)
    
    # Also look for any code blocks
    if not commands:
        code_blocks = re.findall(r"```\w*\s*\n(.*?)\n```", text, re.DOTALL)
        commands.extend(code_blocks)
    
    return [cmd.strip() for cmd in commands if cmd.strip()]


def analyze_prediction(prediction: str) -> dict[str, Any]:
    """Analyze a single prediction patch."""
    if not prediction:
        return {}
    
    # Extract commands from patch
    commands = extract_commands_from_text(prediction)
    
    # Count edit operations
    edit_patterns = {
        "sed": len(re.findall(r"sed\s+-i", prediction)),
        "cat_heredoc": len(re.findall(r"cat\s+<<", prediction)),
        "echo_redirect": len(re.findall(r"echo\s+.*>", prediction)),
        "python": len(re.findall(r"\bpython\b", prediction)),
        "grep": len(re.findall(r"\bgrep\b", prediction)),
        "test": len(re.findall(r"\btest\b|\bpytest\b", prediction)),
    }
    
    return {
        "has_commands": len(commands) > 0,
        "command_count": len(commands),
        "edit_patterns": edit_patterns,
        "patch_length": len(prediction),
    }


def analyze_framework_data(data: dict[str, Any], framework_name: str) -> dict[str, Any]:
    """Analyze data from one framework."""
    print(f"\n📊 Analyzing {framework_name}")
    
    total = len(data)
    submitted = sum(1 for v in data.values() if v.get("exit_status") == "Submitted" or v.get("status") == "Submitted")
    
    # Analyze predictions
    predictions_analyzed = 0
    edit_stats = defaultdict(int)
    command_stats = defaultdict(int)
    
    for instance_id, item in list(data.items())[:min(100, len(data))]:
        prediction = item.get("prediction", "") or item.get("patch", "")
        if prediction:
            analysis = analyze_prediction(prediction)
            predictions_analyzed += 1
            
            for pattern, count in analysis.get("edit_patterns", {}).items():
                edit_stats[pattern] += count
    
    return {
        "total_instances": total,
        "submitted": submitted,
        "submit_rate": (submitted / total * 100) if total > 0 else 0,
        "predictions_analyzed": predictions_analyzed,
        "edit_patterns": dict(edit_stats),
    }


def compare_frameworks(mini_data: dict, gepa_data: dict) -> dict[str, Any]:
    """Compare both frameworks."""
    print("\n" + "=" * 80)
    print("📊 Framework Comparison")
    print("=" * 80)
    
    mini_instances = set(mini_data.keys())
    gepa_instances = set(gepa_data.keys())
    common = mini_instances & gepa_instances
    
    mini_solved = {k for k, v in mini_data.items() 
                   if v.get("exit_status") == "Submitted" or v.get("status") == "Submitted"}
    gepa_solved = {k for k, v in gepa_data.items() 
                   if v.get("exit_status") == "Submitted" or v.get("status") == "Submitted"}
    
    mini_only = mini_solved - gepa_solved
    gepa_only = gepa_solved - mini_solved
    both_solved = mini_solved & gepa_solved
    
    print(f"\n📈 Coverage:")
    print(f"   mini-swe-agent: {len(mini_instances)} instances")
    print(f"   gepa-swe-agent: {len(gepa_instances)} instances")
    print(f"   Common instances: {len(common)}")
    
    print(f"\n✅ Solved:")
    print(f"   mini-swe-agent: {len(mini_solved)} ({len(mini_solved)/len(mini_instances)*100:.1f}%)" if mini_instances else "   mini-swe-agent: 0")
    print(f"   gepa-swe-agent: {len(gepa_solved)} ({len(gepa_solved)/len(gepa_instances)*100:.1f}%)" if gepa_instances else "   gepa-swe-agent: 0")
    print(f"   Both solved: {len(both_solved)}")
    print(f"   mini-only: {len(mini_only)}")
    print(f"   gepa-only: {len(gepa_only)}")
    
    return {
        "mini_total": len(mini_instances),
        "gepa_total": len(gepa_instances),
        "common": len(common),
        "mini_solved": len(mini_solved),
        "gepa_solved": len(gepa_solved),
        "both_solved": len(both_solved),
        "mini_only": list(mini_only)[:20],
        "gepa_only": list(gepa_only)[:20],
    }


def identify_strengths(mini_data: dict, gepa_data: dict, comparison: dict) -> dict[str, Any]:
    """Identify strengths of each framework."""
    strengths = {
        "mini_swe_agent": [],
        "gepa_swe_agent": [],
    }
    
    # Analyze which problem types each solves
    def get_repo(instance_id: str) -> str:
        return instance_id.split("__")[0] if "__" in instance_id else "unknown"
    
    mini_repos = Counter(get_repo(k) for k in comparison.get("mini_only", []))
    gepa_repos = Counter(get_repo(k) for k in comparison.get("gepa_only", []))
    
    if mini_repos:
        top_repo = mini_repos.most_common(1)[0]
        strengths["mini_swe_agent"].append(f"Strong on {top_repo[0]} ({top_repo[1]} instances)")
    
    if gepa_repos:
        top_repo = gepa_repos.most_common(1)[0]
        strengths["gepa_swe_agent"].append(f"Strong on {top_repo[0]} ({top_repo[1]} instances)")
    
    return strengths


def generate_hybrid_recommendations() -> dict[str, Any]:
    """Generate recommendations for hybrid approach."""
    return {
        "core_architecture": {
            "use": "mini-swe-agent's simple loop",
            "reason": "Proven simplicity and effectiveness",
        },
        "error_handling": {
            "use": "mini's strict format checking + gepa's reflection on execution errors",
            "reason": "Balance between strictness and helpful recovery",
        },
        "workflow": {
            "steps": [
                "1. Require reproduction script creation (mini strength)",
                "2. Test after every edit (mini strength)",
                "3. Add reflection prompts only on execution errors (gepa strength)",
                "4. Use first-block fallback very sparingly (gepa feature)",
            ],
        },
        "prompting": {
            "base": "mini's clear, direct prompt structure",
            "additions": [
                "gepa's tool creation guidance for complex cases",
                "Emphasize testing workflow from mini",
            ],
        },
        "limits": {
            "cost": "$3.00 (mini's conservative approach)",
            "steps": "250 (gepa's safety limit)",
        },
    }


def main():
    """Main analysis function."""
    print("=" * 80)
    print("🔍 Comprehensive Framework Analysis")
    print("=" * 80)
    
    # Load data
    mini_repo = "pankajmathur/mini-swe-agent-azure-gpt41mini-verified"
    gepa_repo = "pankajmathur/gepa-swe-agent-v3.0.1-hybrid-azure-gpt41mini-swebench-verified"
    
    mini_data = load_predictions(mini_repo)
    gepa_data = load_predictions(gepa_repo)
    
    if not mini_data and not gepa_data:
        print("\n❌ Could not load data from either dataset")
        return
    
    # Analyze each framework
    mini_stats = analyze_framework_data(mini_data, "mini-swe-agent")
    gepa_stats = analyze_framework_data(gepa_data, "gepa-swe-agent")
    
    # Compare
    comparison = compare_frameworks(mini_data, gepa_data)
    
    # Identify strengths
    strengths = identify_strengths(mini_data, gepa_data, comparison)
    
    # Generate recommendations
    recommendations = generate_hybrid_recommendations()
    
    # Print summary
    print("\n" + "=" * 80)
    print("💪 Strengths")
    print("=" * 80)
    print(f"\nmini-swe-agent:")
    for strength in strengths["mini_swe_agent"]:
        print(f"   - {strength}")
    
    print(f"\ngepa-swe-agent:")
    for strength in strengths["gepa_swe_agent"]:
        print(f"   - {strength}")
    
    print("\n" + "=" * 80)
    print("🎯 Hybrid Recommendations")
    print("=" * 80)
    print(f"\nCore Architecture: {recommendations['core_architecture']['use']}")
    print(f"   Reason: {recommendations['core_architecture']['reason']}")
    print(f"\nError Handling: {recommendations['error_handling']['use']}")
    print(f"\nWorkflow:")
    for step in recommendations['workflow']['steps']:
        print(f"   {step}")
    
    # Save results
    output = {
        "mini_stats": mini_stats,
        "gepa_stats": gepa_stats,
        "comparison": comparison,
        "strengths": strengths,
        "recommendations": recommendations,
    }
    
    output_file = Path("framework_analysis_results.json")
    with open(output_file, "w") as f:
        json.dump(output, f, indent=2)
    
    print(f"\n💾 Detailed results saved to: {output_file}")
    print("=" * 80)


if __name__ == "__main__":
    main()

