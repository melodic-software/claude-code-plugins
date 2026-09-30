# The built-in `Explore` agent: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `Explore` is a built-in subagent described as a "fast read-only search agent for locating code", told not to be used for code review, design-doc auditing, or open-ended analysis because it reads excerpts | The `/claude-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_agents.Explore`) | 2026-09-29 | A release renames or removes `Explore`, or changes its description |
| It is model-invocable, gated, and on a conditional roster; Edit, Write, NotebookEdit, and Agent are disallowed, and it omits CLAUDE.md | Same extraction: `model_invocable: true`, `gated: true`, `roster: conditional`, `disallowed_tools`, `omit_claude_md: true` | 2026-09-29 | A release changes its tools, its CLAUDE.md loading, or its gating |
| `CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS=1` removes it, and a user or project subagent named `Explore` overrides it | <https://code.claude.com/docs/en/sub-agents>, "Built-in subagents" | 2026-09-29 | The page changes how the built-in agents are disabled or overridden |

The denials that make `Explore` a scout rather than this skill's worker (no Write, no preloaded
skill, no CLAUDE.md, no agent ID to resume) are recorded once in
[`../../../reference/parent-contract.md`](../../../reference/parent-contract.md), "The built-in
Explore agent cannot hold this plugin's contract".

## Why the verdict is complementary

`Explore` answers a locate question and hands back excerpts. This skill runs a whole exploration
under the project's conventions and leaves a graded artifact behind. Neither replaces the other:
this skill dispatches `Explore` as its scout.
