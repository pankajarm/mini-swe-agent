# Hybrid Agent Analysis & Implementation

## Executive Summary

This document analyzes the performance differences between **mini-swe-agent** and **gepa-swe-agent** on the same base model (gpt4.1-mini) and proposes a hybrid approach that combines the strengths of both frameworks.

## Key Findings from Analysis

### mini-swe-agent Strengths

1. **Simple Architecture** (123 lines vs 294 lines)
   - Clean 8-line core loop
   - No unnecessary complexity
   - Proven effectiveness

2. **Strict Format Enforcement**
   - Rejects bad format immediately
   - No fallback mechanisms that allow broken responses
   - Forces model to format correctly

3. **Heavy Testing Workflow**
   - 21% of commands are `python` (testing)
   - 140% reproduction script creation rate (multiple per trajectory)
   - Tests after every edit
   - High iteration rate (~26 steps avg, 8.5 error recoveries per trajectory)

4. **Focused Editing**
   - 41% of commands are `sed` (targeted line edits)
   - Simple, precise changes
   - Uses `sed -i` for line modifications

5. **Clear, Direct Prompts**
   - 54-word system prompt
   - ~200-word instance template
   - Minimal hand-holding

### gepa-swe-agent Features

1. **Reflection Mechanism**
   - Adds reflection prompts on errors
   - Can help with complex debugging
   - But may add noise to context

2. **Step Limit Safety**
   - 250 step limit prevents runaway processes
   - Useful for production safety

3. **Tool Creation Guidance**
   - Encourages creating custom Python tools
   - Useful for complex codebases

### Issues Identified

**gepa-swe-agent problems:**
1. First-block fallback allows bad formatting to proceed
2. Reflection prompts may confuse the model (adds ~100 tokens per error)
3. Verbose prompts (400+ words) may overwhelm the model
4. Less emphasis on testing workflow

**mini-swe-agent limitations:**
1. No step limit (could run indefinitely)
2. No reflection on execution errors (though it recovers well without it)

## Hybrid Approach Design

### Core Principles

1. **Use mini's simple loop** - Proven effectiveness
2. **Keep mini's strict format checking** - No fallback
3. **Add gepa's reflection ONLY on execution errors** - Not format errors
4. **Emphasize testing workflow** - mini's strength
5. **Balance limits** - mini's cost ($3) + gepa's step limit (250)

### Implementation Details

#### Architecture
- Base: mini-swe-agent's `DefaultAgent` structure
- Add: Selective execution error reflection (gepa's feature, but minimal)
- Keep: Strict format enforcement (mini's approach)
- Keep: Simple loop (mini's approach)

#### Error Handling
```python
# Format errors: Strict rejection (mini's approach)
if len(actions) != 1:
    raise FormatError(...)  # No fallback

# Execution errors: Minimal reflection (gepa's feature, but selective)
if returncode != 0 and enable_execution_reflection:
    add_minimal_reflection_prompt()  # Much shorter than gepa's default
```

#### Prompting
- System prompt: mini's simple, direct approach
- Instance template: mini's structure + enhanced testing emphasis
- Reflection: Minimal, only on execution errors

#### Limits
- Cost: $3.00 (mini's conservative approach)
- Steps: 250 (gepa's safety limit)

## Expected Improvements

The hybrid approach should:

1. **Maintain mini's high success rate** (74.1% submission rate)
2. **Add safety** with step limits
3. **Improve error recovery** with selective reflection
4. **Preserve simplicity** while adding useful features

## Implementation Files

- `src/minisweagent/agents/hybrid.py` - Hybrid agent implementation
- `src/minisweagent/config/hybrid.yaml` - Hybrid configuration

## Usage

```python
from minisweagent.agents.hybrid import HybridAgent, HybridAgentConfig
from minisweagent.models.azure import AzureModel
from minisweagent.environments.local import LocalEnvironment

model = AzureModel(model_name="gpt-4.1-mini")
env = LocalEnvironment()
agent = HybridAgent(model, env, config_path="hybrid.yaml")

exit_status, message = agent.run(task="Fix the bug...")
```

## Next Steps

1. ✅ Analysis complete
2. ✅ Hybrid agent implemented
3. ⏳ Test on sample SWE-bench instances
4. ⏳ Compare performance vs individual frameworks
5. ⏳ Run full benchmark if promising

## References

- mini-swe-agent analysis: `gepa-swe-agent/docs/CRITICAL_ANALYSIS.md`
- gepa-swe-agent analysis: `gepa-swe-agent/docs/ANALYSIS.md`
- Datasets:
  - mini-swe-agent: https://huggingface.co/datasets/pankajmathur/mini-swe-agent-azure-gpt41mini-verified
  - gepa-swe-agent: https://huggingface.co/datasets/pankajmathur/gepa-swe-agent-v3.0.1-hybrid-azure-gpt41mini-swebench-verified

