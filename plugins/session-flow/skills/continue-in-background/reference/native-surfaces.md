# Native background surfaces: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md), covering the built-in
commands `subtask`, `fork`, and `background`. Each row holds our decision, the pointer to read
live, the date it was checked, and the event that makes it worth checking again.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| Treat `subtask`, `fork`, and `background` (alias `bg`) as user-invocable built-ins the model cannot invoke, so this skill names them and never runs them | Probe: the `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.subtask`, `.fork`, `.background`), observed 2026-09-29 | 2026-10-11 | A release renames or removes one of them or its alias, or changes its invocability or gate |
| Offer `/subtask`, `/fork`, and `/background` as the native ways to move the live conversation; read what each launches, its version floor, and its agent-view dependency live | The `/subtask`, `/fork`, and `/background` rows of [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | Any of those rows changes what the command launches or what it requires |
| Read the history of what `/fork` launches from the release notes, not from memory | [Changelog § 2.1.212](https://code.claude.com/docs/en/changelog#2-1-212) and [§ 2.1.221](https://code.claude.com/docs/en/changelog#2-1-221) | 2026-10-11 | A release note changes what `/fork` launches |

## The `/fork` name discrepancy

The [2.1.77 changelog entry](https://code.claude.com/docs/en/changelog#2-1-77) records a
`/fork` rename that the 2.1.284 binary does not match: the binary registers `fork` and `branch`
as separate commands, the current commands page agrees with the binary, and the 2.1.212 entry
records `/fork` taking its present meaning. Treat the 2.1.77 alias as superseded. As of
2026-10-11. Recheck when a release note or the commands page changes either name.

## Why the verdict is complementary

Each native command moves the live conversation: `/background` moves this session, `/fork` copies
it, and `/subtask` hands a side task to a subagent that reports back. None writes a durable
save-point, redacts the prompt, or checks for uncommitted work before a worktree split. This skill
starts a fresh session from a validated save-point, so the continuation does not depend on the
conversation's history and the save-point outlives it. The person may want either, or both, which
is why the skill offers the native commands rather than replacing them.
