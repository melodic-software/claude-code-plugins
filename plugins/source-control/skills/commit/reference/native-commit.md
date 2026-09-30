# Native commit surfaces: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `commit` is a bundled skill described as "Create a git commit", to be used "whenever you are about to create a commit, whether the user asked for one or it is a step in your current task"; it "gathers git context and applies the required commit workflow (message style, staging rules, attribution)". Argument hint `[guidance]` | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 | 2026-09-29 | A release renames or removes the skill, or changes its description |
| It is model-invocable and user-invocable, and its registration is gated | Same extraction (`model_invocable`, `user_invocable`, `gated` all true) | 2026-09-29 | A release changes its invocability or gate |
| It is undocumented on the commands reference: <https://code.claude.com/docs/en/commands> has no `/commit` row | That page, read 2026-09-29 | 2026-09-29 | The commands page gains a `/commit` row |
| Bundled skills turn off with `disableBundledSkills`, and one bundled skill hides with a `skillOverrides` entry of `"off"` | <https://code.claude.com/docs/en/skills>, bundled skills and skill visibility sections | 2026-09-29 | The skills page changes either setting |
| `commit-push-pr` is a built-in command of type `prompt`, described as "Commit, push, and open a PR". Model-invocable, user-invocable, not gated | The same extraction | 2026-09-29 | A release renames or removes it, or changes its invocability or gate |
| `/commit-push-pr` is undocumented on the commands reference (no row) | <https://code.claude.com/docs/en/commands>, as parsed by `/claude-ops:inventory --docs` on 2026-09-29 | 2026-09-29 | The commands page gains a `/commit-push-pr` row |

## Why the verdict is complementary

The bundled skill applies Claude Code's own commit workflow the same way in every repository.
This skill exists for repositories that declare their own: the layered `source-control.md`
convention and `trailer_policy`, a project commit-msg hook, surgical staging against the four
preconditions, and the per-commit format, exec-bit, and pre-check steps that composing workflows
rely on. Neither replaces the other; both create a commit, so one is chosen per commit.
`/commit-push-pr` goes further than either: it also pushes and opens a PR, so a request to commit
and nothing more never routes to it.
