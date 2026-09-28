---
description: "Move every canonical checkout in a fleet onto the remote default branch and fast-forward it. Divergent dirty work is parked in a linked worktree. Bare invocation prints a dry-run plan. Mutation requires --apply and one confirmation. Use when: 'sync the fleet', 'update all repos to main', 'fast-forward canonical checkouts', 'park my dirty branches and pull'."
user-invocable: true
disable-model-invocation: true
argument-hint: "[<dir>]... [--root <dir>]... [--repo <dir>]... [--named <dir>]... [--config <file>] [--apply] [--yes]"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh:*)
metadata:
  workflow-stage: operator
  summary: Fast-forward canonical checkouts to the remote default branch
  cadence: weekly
---

## Purpose

`/repo-fleet-hygiene:audit` is read-only. `/repo-fleet-hygiene:apply` deletes merged branches.
This skill is the sync verb: each canonical checkout switches to the remote's current default
branch (`git ls-remote --symref origin HEAD`) and `pull --ff-only`s it. Dirty work on a
non-default branch, and a dirty default branch, is parked in a linked worktree through
source-control's `worktree-create.sh --existing-branch`.

## Scope ladder

First hit wins:

1. Explicit `--repo`, `--root`, or a bare path.
2. Fleet config (`--config`, else the project file, else `~/.claude/repo-fleet-hygiene.conf`).
3. `--named` paths from the conversation.
4. `ghq root`, when `ghq` is installed.
5. The current working directory, when it is a Git checkout.
6. Exit 3. The message names the rungs. The project directory is not an implicit repo.

`/repo-fleet-hygiene:audit` uses the same fallback when it has no explicit or config scope.

## Confirmation

| Flags | Behavior |
|---|---|
| (default) | Dry-run plan. Nothing changes. |
| `--apply` on a terminal | One prompt for the whole plan. Decline changes nothing. |
| `--apply` without a terminal | Exit 3. Nothing changes. |
| `--apply --yes` | Apply. |

Non-fast-forward, dubious ownership, and a partial stash apply are skipped and reported.
The script does not reset a branch.

Pass `--worktree-root` and `--worktree-create` when a park is planned. The create helper is
`worktree-create.sh` in the source-control plugin. `--existing-branch` checks out the branch
that already holds the work.

Run:

```bash
${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh --project-dir "${CLAUDE_PROJECT_DIR}" <quoted-arguments>
```

## Next

`/repo-fleet-hygiene:audit` after canonical checkouts are on their default branches.

## Gotchas

- A clean non-default branch is checked out away from, not deleted. The branch remains.
- `pull --ff-only` refuses a history that diverged. That repo is skipped.
- Do not point this at `repo-hygiene:clean tree-batch`. That verb is destructive and is not this skill.
