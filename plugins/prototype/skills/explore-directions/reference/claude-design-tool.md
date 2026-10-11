# The built-in `ClaudeDesign` tool: verification record

Detail behind the `## Boundary, the built-in ClaudeDesign tool` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again. The `visualization` plugin's `visualize` skill keeps its
own record against the same surface.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| A built-in tool named `ClaudeDesign` is registered model-invocable, not user-invocable, gated and not deferred; its search hint ties it to existing claude.ai/design projects | Probe: the `ClaudeDesign` records in `docs/native-surfaces/records.json` (the 2.1.285 `/harness-ops:inventory` binary extraction, `builtin_tools` lane) | 2026-09-29 | A release renames or removes the tool, or changes its invocability, gating, or deferral |
| Its description presents it as the editor for a team's existing Claude Design projects (decks, prototypes, landing pages, UI mockups) backed by the team's design system; the exact string is held in the probe record, not here | Probe: the same records (targeted string search of the 2.1.285 binary) | 2026-09-30 | A release changes the description |
| It lists, reads, copies and writes files in existing projects, with a plan step for writes; the operation names are in the probe record. It does not create a new Design artifact; that is the bundled `design` skill's job | Probe: the same records (string search of the same binary) | 2026-09-30 | A release adds, removes, or renames an operation |
| A write needs either a one-time project approval in an interactive session or the tool's plan step, and the tool refuses writes in some execution contexts; the probe record lists which | Probe: the same records (the permission check's denial reasons) | 2026-09-30 | A release changes the approval flow or the denial cases |
| The tools reference does not list `ClaudeDesign` | The docs cross-check of the same extraction against <https://code.claude.com/docs/en/tools-reference> | 2026-09-29 | The tools reference adds it |

## Why the verdict is complementary

`ClaudeDesign` edits a project the person's team already keeps on claude.ai/design. This skill
builds throwaway variants to answer which direction a page should take, then discards them. When
the person points at an existing project, the work belongs in that project; otherwise the
throwaway comparison is the job.
