# The built-in worktree tools: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `EnterWorktree` is a built-in tool described as "Creates an isolated worktree (via git or configured hooks) and switches the session into it"; model-invocable, not user-invocable, not gated, deferred | Upstream: the `EnterWorktree` row on <https://code.claude.com/docs/en/tools-reference>, which lists it among the tools Claude uses ("Creates an isolated git worktree and switches into it"). Invocability and gating: the `/claude-ops:inventory` extraction of the installed 2.1.285 binary (`builtin_tools.EnterWorktree`) | 2026-10-01 | A release renames or removes the tool, changes its description or invocability, or the tools reference row changes |
| Given a `path`, `EnterWorktree` switches into an existing worktree instead of creating one | The `EnterWorktree` row on <https://code.claude.com/docs/en/tools-reference> | 2026-10-01 | The tools reference row changes or disappears |
| `ExitWorktree` is a built-in tool described as "Exits a worktree session created by EnterWorktree and restores the original working directory"; model-invocable, not user-invocable, not gated, deferred | Upstream: the `ExitWorktree` row on <https://code.claude.com/docs/en/tools-reference> ("Exits a worktree session and returns to the original directory"). Invocability and gating: the same extraction (`builtin_tools.ExitWorktree`) | 2026-10-01 | A release renames or removes the tool, makes it remove the worktree, or the tools reference row changes |
| `ExitWorktree` is not available to subagents that already run in their own working directory | The `ExitWorktree` row on <https://code.claude.com/docs/en/tools-reference> | 2026-10-01 | The tools reference row changes |

## Why the verdict is complementary

The tools move a session in and out of a worktree. This skill decides where a worktree is created
(an external root, never inside the repository), claims it, and later inventories and removes it.
`create` ends by calling `EnterWorktree(path:)`, so the two compose in sequence and neither
replaces the other. Entering an existing worktree also runs through this skill: the tool alone
does not check the claim another live session may hold, and the worktree lock does not block
writes.
