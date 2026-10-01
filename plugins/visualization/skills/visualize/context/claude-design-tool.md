# The built-in `ClaudeDesign` tool: verification record

Detail behind the `ClaudeDesign` part of the `## Boundary` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again. The `prototype` plugin's `explore-directions` skill keeps
its own record against the same surface.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| A built-in tool named `ClaudeDesign` (user-facing name "Claude Design") is registered model-invocable, not user-invocable, gated, and not deferred, with the search hint "work with Claude Design (claude.ai/design) projects" | A binary extraction of the installed 2.1.285 build (the `builtin_tools` lane) | 2026-09-29 | A release renames or removes the tool, or changes its invocability, gating, or deferral |
| Its description reads "Work with Claude Design (claude.ai/design)", an em dash, then "a collaborative canvas for decks, prototypes, landing pages, and UI mockups backed by your team's design system." The extraction reports the description as unresolved, so this string comes from a targeted search | String search of the same 2.1.285 binary | 2026-09-30 | A release changes the description |
| Its operations include `list`, `get_project`, `write_files`, `create_support_js`, `copy_files`, `finalize_plan` (which returns a `plan_token`), `list_members`, and `get_conversation`. It works on existing projects; creating a new Design artifact is the bundled `design` skill's job | String search of the same binary | 2026-09-30 | A release adds, removes, or renames an operation |
| A write needs either a one-time durable project approval, granted in an interactive session, or a `plan_token` from `finalize_plan`. Writes are denied in subagents, in non-interactive sessions, and in plan mode without a `plan_token` | String search of the same binary (the permission check's `safetyCheck` reasons) | 2026-09-30 | A release changes the approval flow or the denial cases |
| The tools reference does not list `ClaudeDesign` | The docs cross-check of the same extraction against <https://code.claude.com/docs/en/tools-reference> | 2026-09-29 | The tools reference adds it |

## Why the verdict is complementary

`ClaudeDesign` edits a project the person's team already keeps on claude.ai/design. This skill
picks a visual form and medium for what is in the conversation and renders it inline, to a local
file, or as a published Artifact. When the person points at an existing project, the work belongs
in that project; otherwise rendering its own output is the job.
