---
type: llm
arm: both
---

PASS if the answer says fast-check runs as the brief-reviewer agent with model sonnet and effort max, passed explicitly on the Agent call at dispatch so they override the agent file's opus/high pin. Adding that the member is skipped (not run on another setting) when the Claude Code version is too old to set effort is fine.

FAIL if the answer says it runs on opus or effort high because of the agent pin, that the effort is ignored, that a different agent runs it, or that an unsupported effort silently falls back to another value.
