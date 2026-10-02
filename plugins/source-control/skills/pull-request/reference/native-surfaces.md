# Native PR surfaces: verification record

Detail behind the `## Boundary, native Claude Code surfaces` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again. "The extraction" below is the `/harness-ops:inventory`
extraction of the installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `pr` is a bundled skill described as "Create a GitHub pull request", to be used "whenever you are about to open a PR, whether the user asked for one or it is a step in your current task"; it "gathers branch context and applies the required PR workflow (gh CLI, title/body format, attribution)". Model-invocable, user-invocable, gated | The extraction | 2026-09-29 | A release renames or removes it, or changes its invocability or gate |
| `pr` is undocumented on <https://code.claude.com/docs/en/commands> (no `/pr` row) | That page, read 2026-09-29 | 2026-09-29 | The page gains a `/pr` row |
| `commit-push-pr` is a built-in command of type `prompt`, described as "Commit, push, and open a PR". Model-invocable, user-invocable, not gated | The extraction | 2026-09-29 | A release renames or removes it, or changes its invocability or gate |
| `/commit-push-pr` is undocumented on the commands page; the changelog records that it no longer auto-approves git/gh commands with dangerous flags (`--force`, `--amend`, `--no-verify`) and auto-allows `git push` to the configured push remote | <https://code.claude.com/docs/en/commands>; the Claude Code changelog, <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md> | 2026-09-29 | The commands page gains a row, or a changelog entry names `/commit-push-pr` |
| `autofix-pr` is a built-in command described as "Monitor and autofix any issues with the current PR". User-invocable only (not model-invocable), hidden, gated | The extraction | 2026-09-29 | A release changes its invocability, visibility, or gate |
| `/autofix-pr [prompt]` spawns a cloud session that watches the current branch's PR and pushes fixes when CI fails or reviewers leave comments; it detects the PR with `gh pr view`, fixes every CI failure and review comment by default, takes a prompt to narrow that, and requires the `gh` CLI and access to cloud sessions | The `/autofix-pr` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | That row changes |
| Bundled skills turn off with `disableBundledSkills`, and one bundled skill hides with a `skillOverrides` entry of `"off"` | <https://code.claude.com/docs/en/skills> | 2026-09-29 | The skills page changes either setting |

## Why the verdict is complementary

`pr` and `/commit-push-pr` stop at an open PR and apply Claude Code's generic format. This skill
applies the repository's own title pattern, body contract, and draft-first rule, then carries the
PR through ready, monitoring, and merge. `/autofix-pr` monitors too, but in a cloud session that
fixes everything by default and keeps running after the local session ends; this skill's monitor
loop runs locally, gates every CI fix on research, and classifies each review finding with a
reply before fixing. The model offers `/autofix-pr` to the person because only the person runs it.
