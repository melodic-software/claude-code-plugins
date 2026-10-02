# The built-in `Plan` agent: verification record

Detail behind the `Plan` agent's Boundary section in [SKILL.md](../SKILL.md). Each row is a
four-part record: the claim, the basis it rests on, the date it was checked, and the event that
makes it worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `Plan` is a built-in subagent described as a "software architect agent for designing implementation plans" that returns step-by-step plans | The `/harness-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_agents.Plan`) | 2026-09-29 | A release renames or removes `Plan`, or changes its description |
| It is model-invocable, gated, and on a conditional roster; Edit, Write, NotebookEdit, Agent, and ExitPlanMode are disallowed, and it omits CLAUDE.md | Same extraction: `model_invocable: true`, `gated: true`, `roster: conditional`, `disallowed_tools`, `omit_claude_md: true` | 2026-09-29 | A release changes its tools, its CLAUDE.md loading, or its gating |
| Its documented role is research during plan mode, gathering context before a plan is presented; `CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS=1` removes it | <https://code.claude.com/docs/en/sub-agents>, "Built-in subagents" | 2026-09-29 | The page changes the agent's role or how it is disabled |

## Why the verdict is complementary

`Plan` returns an approach to whoever dispatched it and keeps nothing. This skill runs the
planning discipline, gets the person's approval, and persists PLAN.md for a cleared session. The
skill can use `Plan` to gather context; the subagent cannot stand in for the approved plan.
