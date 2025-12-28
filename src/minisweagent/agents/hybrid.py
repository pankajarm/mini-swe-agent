"""
Hybrid agent combining strengths of mini-swe-agent and gepa-swe-agent.

Key features:
- mini-swe-agent's simple loop structure
- mini-swe-agent's strict format checking
- gepa-swe-agent's reflection on execution errors only (not format errors)
- mini-swe-agent's emphasis on testing workflow
- Balanced limits: mini's cost ($3) + gepa's step limit (250)
"""

import re
import subprocess
import time

from jinja2 import StrictUndefined, Template
from pydantic import BaseModel

from minisweagent import Environment, Model
from minisweagent.agents.default import (
    AgentConfig,
    ExecutionTimeoutError,
    FormatError,
    LimitsExceeded,
    NonTerminatingException,
    Submitted,
    TerminatingException,
)


class HybridAgentConfig(AgentConfig):
    """Configuration for hybrid agent."""
    # Use mini's cost limit but gepa's step limit
    step_limit: int = 250
    cost_limit: float = 3.0
    
    # Hybrid-specific: reflection only on execution errors
    enable_execution_reflection: bool = True
    execution_reflection_template: str = ""


class HybridAgent:
    """
    Hybrid agent combining best practices from both frameworks.
    
    From mini-swe-agent:
    - Simple, clean loop structure
    - Strict format enforcement (no fallback)
    - Clear, direct prompts
    
    From gepa-swe-agent:
    - Reflection on execution errors (not format errors)
    - Step limit for safety
    """
    
    def __init__(self, model: Model, env: Environment, *, config_class: type = HybridAgentConfig, **kwargs):
        self.config = config_class(**kwargs)
        self.messages: list[dict] = []
        self.model = model
        self.env = env
        self.extra_template_vars = {}
        self._execution_reflections = 0

    def render_template(self, template: str, **kwargs) -> str:
        template_vars = self.config.model_dump() | self.env.get_template_vars() | self.model.get_template_vars()
        return Template(template, undefined=StrictUndefined).render(
            **kwargs, **template_vars, **self.extra_template_vars
        )

    def add_message(self, role: str, content: str, **kwargs):
        self.messages.append({"role": role, "content": content, "timestamp": time.time(), **kwargs})

    def run(self, task: str, **kwargs) -> tuple[str, str]:
        """Run step() until agent is finished. Return exit status & message"""
        self.extra_template_vars |= {"task": task, **kwargs}
        self.messages = []
        self._execution_reflections = 0
        
        self.add_message("system", self.render_template(self.config.system_template))
        self.add_message("user", self.render_template(self.config.instance_template))
        
        # mini-swe-agent's simple loop
        while True:
            try:
                self.step()
            except NonTerminatingException as e:
                self.add_message("user", str(e))
            except TerminatingException as e:
                self.add_message("user", str(e))
                return type(e).__name__, str(e)

    def step(self) -> dict:
        """Query the LM, execute the action, return the observation."""
        return self.get_observation(self.query())

    def query(self) -> dict:
        """Query the model and return the response."""
        if 0 < self.config.step_limit <= self.model.n_calls:
            raise LimitsExceeded()
        if 0 < self.config.cost_limit <= self.model.cost:
            raise LimitsExceeded()
        response = self.model.query(self.messages)
        self.add_message("assistant", **response)
        return response

    def get_observation(self, response: dict) -> dict:
        """Execute the action and return the observation."""
        output = self.execute_action(self.parse_action(response))
        
        # Build observation with optional execution reflection
        observation = self._build_observation(output)
        self.add_message("user", observation)
        
        return output

    def _build_observation(self, output: dict) -> str:
        """Build observation with optional reflection on execution errors only."""
        base_observation = self.render_template(self.config.action_observation_template, output=output)
        
        # Add reflection ONLY on execution errors (not format errors)
        # This is gepa's strength, but applied selectively
        if (self.config.enable_execution_reflection and 
            output.get("returncode", 0) != 0 and
            not isinstance(output.get("action", ""), Exception)):
            self._execution_reflections += 1
            
            if self.config.execution_reflection_template:
                reflection = self.render_template(self.config.execution_reflection_template, output=output)
            else:
                # Minimal reflection prompt (much shorter than gepa's default)
                reflection = "\n\n<reflection>What went wrong? How can you fix it?</reflection>"
            
            return base_observation + reflection
        
        return base_observation

    def parse_action(self, response: dict) -> dict:
        """Parse the action from the message. Strict format checking (mini's approach)."""
        actions = re.findall(self.config.action_regex, response["content"], re.DOTALL)
        
        # mini-swe-agent's strict enforcement - NO fallback
        if len(actions) == 1:
            return {"action": actions[0].strip(), **response}
        
        # Always raise on format errors - no fallback like gepa
        raise FormatError(self.render_template(self.config.format_error_template, actions=actions))

    def execute_action(self, action: dict) -> dict:
        try:
            output = self.env.execute(action["action"])
        except (TimeoutError, subprocess.TimeoutExpired) as e:
            output = e.output.decode("utf-8", errors="replace") if getattr(e, "output", None) else ""
            raise ExecutionTimeoutError(
                self.render_template(self.config.timeout_template, action=action, output=output)
            )
        self.has_finished(output)
        return output | {"action": action["action"]}

    def has_finished(self, output: dict[str, str]):
        """Raises Submitted exception with final output if the agent has finished its task."""
        lines = output.get("output", "").lstrip().splitlines(keepends=True)
        if lines and lines[0].strip() in ["MINI_SWE_AGENT_FINAL_OUTPUT", "COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT", "GEPA_SUBMIT"]:
            raise Submitted("".join(lines[1:]))

