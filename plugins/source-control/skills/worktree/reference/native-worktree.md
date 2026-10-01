# The built-in worktree tools: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `EnterWorktree` is a built-in tool described as "Creates an isolated worktree (via git or configured hooks) and switches the session into it"; model-invocable, not user-invocable, not gated, deferred | Upstream: the `EnterWorktree` row on <https://code.claude.com/docs/en/tools-reference>, which lists it among the tools Claude uses ("Creates an isolated git worktree and switches into it"). Invocability and gating: the `/claude-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.EnterWorktree`) | 2026-10-01 | A release renames or removes the tool, changes its description or invocability, or the tools reference row changes |
| Given a `path`, `EnterWorktree` switches into an existing worktree instead of creating one | The `EnterWorktree` row on <https://code.claude.com/docs/en/tools-reference> | 2026-10-01 | The tools reference row changes or disappears |
| `ExitWorktree` is a built-in tool described as "Exits a worktree session created by EnterWorktree and restores the original working directory"; model-invocable, not user-invocable, not gated, deferred | Upstream: the `ExitWorktree` row on <https://code.claude.com/docs/en/tools-reference> ("Exits a worktree session and returns to the original directory"). Invocability and gating: the same extraction (`builtin_tools.ExitWorktree`) | 2026-10-01 | A release renames or removes the tool, changes its description or invocability, or the tools reference row changes |
| `ExitWorktree` takes an `action`: `"keep"` leaves the worktree and its branch on disk; `"remove"` deletes both, is marked destructive (user-facing name "Cleaning up worktree"), and refuses a worktree with uncommitted files or unmerged commits unless `discard_changes` is true. It will not remove a worktree entered with `EnterWorktree(path:)`; for those, use `action: "keep"` | The tool's input schema, `isDestructive`, and the `EnterWorktree` prompt ("ExitWorktree will not remove a worktree entered this way; use `action: "keep"`") in the installed 2.1.285 binary, read by string search. Upstream, <https://code.claude.com/docs/en/worktrees> describes the same keep-or-remove choice at session exit ("Removing deletes the worktree directory and its branch"); the tools reference row does not list the actions | 2026-10-01 | A release changes the `action` values, what `remove` deletes, or whether a path-entered worktree can be removed, or the tools reference documents the actions |
| `EnterWorktree(path:)` refuses a worktree whose git lock reason is Claude Code's own `claude … (pid N …)` form naming another live process ("belongs to another running Claude Code session"). Any other lock reason, including the session claims this plugin writes (`… session <id> since …`), does not stop it | The `EnterWorktree` path validation and its lock-reason matcher in the installed 2.1.285 binary, read by string search; undocumented on <https://code.claude.com/docs/en/tools-reference> and <https://code.claude.com/docs/en/worktrees> | 2026-10-01 | A release changes which lock reasons the tool honors, or either page documents the check |
| `ExitWorktree` is not available to subagents that already run in their own working directory | The `ExitWorktree` row on <https://code.claude.com/docs/en/tools-reference> | 2026-10-01 | The tools reference row changes |

## Why the verdict is complementary

The tools move a session in and out of a worktree. This skill decides where a worktree is created
(an external root, never inside the repository), claims it, and later inventories and removes it.
`create` ends by calling `EnterWorktree(path:)`, so the two compose in sequence and neither
replaces the other. Entering an existing worktree also runs through this skill. The tool checks
the git worktree lock, but honors only Claude Code's own lock form naming a live process. This
skill's `check-enter` also reads the session claims this plugin writes, which the tool does not
recognize, and it stops on an unclaimed worktree until this session claims it. Removal stays with
`cleanup`, because `ExitWorktree` will not remove a worktree entered by `path`, which is how this
skill enters.
