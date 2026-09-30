# The bundled `batch` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `batch` is a bundled skill described as "Research and plan a large-scale change, then execute it in parallel across 5–30 isolated worktree agents that each open a PR", argument hint `<instruction>` | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 | 2026-09-29 | A release renames or removes it, or changes its description |
| Its registration disables model invocation: the person runs it, the model does not | Same extraction (`disable_model_invocation` true, `model_invocable` false, `user_invocable` true) | 2026-09-29 | A release changes its invocability |
| `/batch <instruction>` researches the codebase, decomposes the work into 5 to 30 independent units, and presents a plan; once approved it spawns one background subagent per unit in an isolated worktree, and each implements its unit, runs tests, and publishes its change. It requires a git repository or a `WorktreeCreate` hook that creates the worktrees; outside a git repository it requires v2.1.281 or later | The `/batch` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | That row changes |
| Bundled skills turn off with `disableBundledSkills`, and one bundled skill hides with a `skillOverrides` entry of `"off"` | <https://code.claude.com/docs/en/skills> | 2026-09-29 | The skills page changes either setting |

## Why the verdict is complementary

`/batch` plans and executes in one run: it does its own research and decomposition, and the
units are independent by construction, each ending in its own PR. This skill starts where a plan
already exists and has been approved, runs phases in order with fences composed together per
wave, verifies every return against direct evidence, and gates each phase on a fresh-context
verifier. A large mechanical change with no plan is `/batch`'s case; a planned, ordered,
verified execution is this skill's.
