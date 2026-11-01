# Native commit surfaces: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `commit` is a bundled skill that creates a git commit through Claude Code's own generic commit workflow, taking optional guidance as its argument | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 | 2026-09-29 | A release renames or removes the skill, or changes its description |
| It is model-invocable and user-invocable, and its registration is gated | Same extraction (`model_invocable`, `user_invocable`, `gated` all true) | 2026-09-29 | A release changes its invocability or gate |
| It has no row in [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | That section, read 2026-10-11 | 2026-10-11 | The section gains a `/commit` row |
| Bundled skills have a global off switch and a per-skill hide setting | The pull-request skill's [native surfaces record](../../pull-request/reference/native-surfaces.md), last row, owns the pointer | 2026-10-11 | That row changes |
| `commit-push-pr` is a built-in command that also pushes and opens a PR, and has no commands-page row | The pull-request skill's [native surfaces record](../../pull-request/reference/native-surfaces.md), its `commit-push-pr` rows, owns both | 2026-10-11 | Those rows change |

## Why the verdict is complementary

The bundled skill applies Claude Code's own commit workflow the same way in every repository.
This skill exists for repositories that declare their own: the layered `source-control.md`
convention and `trailer_policy`, a project commit-msg hook, surgical staging against the four
preconditions, and the per-commit format, exec-bit, and pre-check steps that composing workflows
rely on. Neither replaces the other; both create a commit, so one is chosen per commit.
`/commit-push-pr` goes further than either: it also pushes and opens a PR, so a request to commit
and nothing more never routes to it.
