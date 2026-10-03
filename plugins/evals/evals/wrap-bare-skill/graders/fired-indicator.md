---
type: llm
arm: both
---

PASS if the answer says to tell whether the skill was used from a `tool_used` grader on the Skill tool (optionally with `input_match` naming the skill).

FAIL if the answer relies on the score delta, the trace alone, a regex grader, or a `tool_used` grader on another tool; says no such grader is needed; or later contradicts or retracts this.
