# Native background surfaces: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md), covering the built-in
commands `subtask`, `fork`, and `background`. Each row is a four-part record: the claim, the basis
it rests on, the date it was checked, and the event that makes it worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `subtask` is a built-in command, "Send a subagent off with your full context; its result comes back here", argument `<task>`, user-invocable, not model-invocable, gated | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.subtask`) | 2026-09-29 | A release renames or removes `subtask`, or changes its invocability or gate |
| `fork` is a built-in command, "Spawn a background agent that inherits the full conversation", argument `<directive>`, user-invocable, not model-invocable, gated | Same extraction (`builtin_commands.fork`) | 2026-09-29 | A release renames or removes `fork`, or changes its description, invocability, or gate |
| `background` is a built-in command with alias `bg`, "Send this session to the background and free the terminal", argument `[prompt]`, user-invocable, not model-invocable, gated | Same extraction (`builtin_commands.background`) | 2026-09-29 | A release renames or removes `background` or its alias, or changes its invocability or gate |
| `/subtask` spawns a forked subagent whose result returns to this conversation; it needs 2.1.212 or later and is unavailable when agent view is turned off | The `/subtask <task>` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes |
| `/fork [prompt]` copies the conversation into a new background session and keeps working here; on 2.1.161 through 2.1.211, and whenever agent view is off, it starts a forked subagent instead. The copy is told to create its own worktree before code changes (2.1.221 or later) | The `/fork [prompt]` row on the commands page; changelog 2.1.212 ("the in-session subagent it used to launch is now `/subtask`") and 2.1.221 | 2026-09-29 | The commands page row changes, or a release note changes what `/fork` launches |
| `/background [prompt]` detaches the current session as a background agent, managed with `claude agents`; alias `/bg` | The `/background [prompt]` row on the commands page | 2026-09-29 | The commands page row changes |

## The `/fork` name discrepancy

The Claude Code changelog at 2.1.77 reads "Renamed `/fork` to `/branch` (`/fork` still works as an
alias)". The 2.1.284 binary does not match that entry: it registers `fork` as its own command with
the background-agent description above, and registers `branch` separately ("Create a branch of the
current conversation at this point") with no aliases. The current commands page agrees with the
binary, and the 2.1.212 changelog entry records `/fork` taking its present meaning. Treat the 2.1.77
alias as superseded. Recheck when a release note or the commands page changes either name.

## Why the verdict is complementary

Each native command moves the live conversation: `/background` moves this session, `/fork` copies
it, and `/subtask` hands a side task to a subagent that reports back. None writes a durable
save-point, redacts the prompt, or checks for uncommitted work before a worktree split. This skill
starts a fresh session from a validated save-point, so the continuation does not depend on the
conversation's history and the save-point outlives it. The person may want either, or both, which
is why the skill offers the native commands rather than replacing them.
