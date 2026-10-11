# The built-in worktree tools: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `EnterWorktree` is a built-in tool that creates an isolated worktree, or switches into an existing one, and moves the session into it; model-invocable, not user-invocable, not gated, deferred | Upstream: [worktrees: ask Claude to create a worktree](https://code.claude.com/docs/en/worktrees#ask-claude-to-create-a-worktree), which links the tool's tools-reference row. Invocability and gating: the `/harness-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.EnterWorktree`) | Docs section: 2026-10-11. Binary extraction: 2026-10-01 | A release renames or removes the tool or changes its invocability, or that section changes |
| Given a `path`, `EnterWorktree` switches into an existing worktree instead of creating one. The path form has limits that bear on `create`'s final `EnterWorktree(path:)` call on an external root; read them live before relying on that call | Pointer: the `EnterWorktree` row of the tool table on <https://code.claude.com/docs/en/tools-reference>. The row has no anchor of its own (the table sits above the page's first section heading; checked 2026-10-11), so the anchored companion is [worktrees: ask Claude to create a worktree](https://code.claude.com/docs/en/worktrees#ask-claude-to-create-a-worktree) | 2026-10-11 | The `EnterWorktree` row or that section changes what the `path` form may target or when it asks for approval |
| `ExitWorktree` is a built-in tool that leaves a worktree session and restores the original directory; model-invocable, not user-invocable, not gated, deferred | Upstream: [worktrees: resume a worktree session](https://code.claude.com/docs/en/worktrees#resume-a-worktree-session), which links the tool's tools-reference row. Invocability and gating: the same extraction (`builtin_tools.ExitWorktree`) | Docs section: 2026-10-11. Binary extraction: 2026-10-01 | A release renames or removes the tool or changes its invocability, or that section changes |
| `ExitWorktree` takes an `action`: `"keep"` leaves the worktree and its branch on disk; `"remove"` deletes both, is marked destructive, and refuses a worktree with uncommitted files or unmerged commits unless `discard_changes` is true. It will not remove a worktree entered with `EnterWorktree(path:)`; for those, use `action: "keep"` | The tool's input schema, `isDestructive`, and the `EnterWorktree` prompt in the installed 2.1.285 binary, read by string search. Upstream, [worktrees: clean up worktrees](https://code.claude.com/docs/en/worktrees#clean-up-worktrees) describes the same keep-or-remove choice at session exit; the tools reference row does not list the actions | Docs section: 2026-10-11. Binary string search: 2026-10-01 | A release changes the `action` values, what `remove` deletes, or whether a path-entered worktree can be removed, or the tools reference documents the actions |
| `EnterWorktree(path:)` refuses a worktree whose git lock reason is Claude Code's own `claude … (pid N …)` form naming another live process. Any other lock reason, including the session claims this plugin writes (`… session <id> since …`), does not stop it | The `EnterWorktree` path validation and its lock-reason matcher in the installed 2.1.285 binary, read by string search; undocumented on <https://code.claude.com/docs/en/tools-reference> and [worktrees](https://code.claude.com/docs/en/worktrees#ask-claude-to-create-a-worktree) | 2026-10-01 | A release changes which lock reasons the tool honors, or either page documents the check |
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
