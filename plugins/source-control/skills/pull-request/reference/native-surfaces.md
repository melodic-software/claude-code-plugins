# Native PR surfaces: verification record

Detail behind the `## Boundary, native Claude Code surfaces` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again. "The extraction" below is the `/harness-ops:inventory`
extraction of the installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `pr` is a bundled skill that opens a GitHub pull request through Claude Code's own generic PR workflow. Model-invocable, user-invocable, gated | The extraction | 2026-09-29 | A release renames or removes it, or changes its invocability or gate |
| `pr` has no row in [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | That section, read 2026-10-11 | 2026-10-11 | The section gains a `/pr` row |
| `commit-push-pr` is a built-in prompt command that commits, pushes, and opens a PR in one step. Model-invocable, user-invocable, not gated | The extraction | 2026-09-29 | A release renames or removes it, or changes its invocability or gate |
| `/commit-push-pr` has no row in [commands: all commands](https://code.claude.com/docs/en/commands#all-commands); the Claude Code changelog records which git and gh commands it auto-approves | That section, read 2026-10-11; the changelog releases that name it, [2.1.229](https://code.claude.com/docs/en/changelog#2-1-229) and [2.1.206](https://code.claude.com/docs/en/changelog#2-1-206) | 2026-10-11 | The section gains a row, or a release after 2.1.229 names `/commit-push-pr` |
| `autofix-pr` is a built-in command that watches the current PR and fixes what fails. User-invocable only (not model-invocable), hidden, gated | The extraction | 2026-09-29 | A release changes its invocability, visibility, or gate |
| `/autofix-pr` hands the current branch's PR to a cloud session that pushes fixes; its default scope, prompt argument, and requirements are on its row | The `/autofix-pr` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | That row changes |
| Auto-fix has repository and plan preconditions, and a cloud session keeps running after the local machine closes | [Auto-fix pull requests](https://code.claude.com/docs/en/claude-code-on-the-web#auto-fix-pull-requests) and the plan-eligibility note on [that page](https://code.claude.com/docs/en/claude-code-on-the-web), which has no anchor of its own (it sits above the page's first section heading; checked 2026-10-11) | 2026-10-11 | Either passage changes a precondition or the session lifetime |
| Auto-fix cannot react to a merge conflict on its own, and its thread replies post under the person's GitHub account, where they can trigger comment-driven automation | [How Claude responds to PR activity](https://code.claude.com/docs/en/claude-code-on-the-web#how-claude-responds-to-pr-activity) | 2026-10-11 | That section changes any of the three |
| Cloud sessions draw on the same rate limits as the account's other Claude usage | [Limitations](https://code.claude.com/docs/en/claude-code-on-the-web#limitations), the rate-limit bullet | 2026-10-11 | That bullet changes |
| `/background` (alias `/bg`) detaches the current session to a local background agent and frees the terminal | The `/background` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | That row changes |
| Bundled skills have a global off switch and a per-skill hide setting; the commit skill's native record cites this row | [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) and [override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | 2026-10-11 | Either section changes a setting name or what it covers |

## Why the verdict is complementary

`pr` and `/commit-push-pr` stop at an open PR and apply Claude Code's generic format. This skill
applies the repository's own title pattern, body contract, and draft-first rule, then carries the
PR through ready, monitoring, and merge. `/autofix-pr` monitors too, but in a cloud session that
fixes everything by default and keeps running after the local session ends; this skill's monitor
loop runs locally, gates every CI fix on research, and classifies each review finding with a
reply before fixing. The model offers `/autofix-pr` to the person because only the person runs it.
