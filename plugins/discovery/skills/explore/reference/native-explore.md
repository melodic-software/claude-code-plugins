# The built-in `Explore` agent: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `Explore` is a built-in read-only locator whose own description steers it away from review and open-ended analysis, because it reads excerpts | Probe: the `/harness-ops:inventory` extraction of the installed 2.1.288 binary (`builtin_agents.Explore`) | 2026-10-02 | A release renames or removes `Explore`, or changes its description |
| It is model-invocable, gated, and on a conditional roster; it cannot edit files or spawn an agent, and it omits CLAUDE.md | Same extraction: `model_invocable: true`, `gated: true`, `roster: conditional`, `omit_claude_md: true`; the current disallowed-tool list is `builtin_agents.Explore.disallowed_tools` in a fresh run | 2026-10-02 | A release changes its tools, its CLAUDE.md loading, or its gating |
| A session can disable it or override it with its own subagent, so the scout may be absent or replaced | Pointer: when deciding whether the scout in this session is the built-in one, fetch [subagents: built-in subagents](https://code.claude.com/docs/en/sub-agents#built-in-subagents) live | 2026-10-11 | That section changes how the built-in agents are disabled or overridden |

The denials that make `Explore` a scout rather than this skill's worker (no Write, no preloaded
skill, no CLAUDE.md, no agent ID to resume) are recorded once in
[`../../../reference/parent-contract.md`](../../../reference/parent-contract.md), "The built-in
Explore agent cannot hold this plugin's contract".

## Why the verdict is complementary

`Explore` answers a locate question and hands back excerpts. This skill runs a whole exploration
under the project's conventions and leaves a graded artifact behind. Neither replaces the other:
this skill dispatches `Explore` as its scout.
