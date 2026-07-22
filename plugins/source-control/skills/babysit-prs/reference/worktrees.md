# Worktrees

Babysit PR worktrees are ephemeral scratch, not durable state. They live under `<worktree-root>`,
one per PR — find the existing worktree for a PR or create it; never share a checkout between
workers, and never place a worktree inside another checkout. Durable state belongs in GitHub,
committed PR branches, and `<state-dir>`. Angle-bracket slots (`<worktree-root>`, `<state-dir>`)
are filled from the effective-configuration block in this skill's `SKILL.md`, which renders every
key's resolved value and its unset fallback; `<worktree-root>` defaults to the `worktrees`
subdirectory of the plugin data directory, and `<state-dir>` is its `state/babysit-prs`
subdirectory.

## Policy

- At the start of a queue run holding the queue lease, remove only unleased clean babysit
  worktrees for merged or closed PRs. Snapshot and single-PR modes never run global cleanup.
- After a PR result is integrated, keep its worker lease held while removing only that PR's clean
  worktree with `--pr`, its matching `--lease-token`, and `--prune-open-clean`; then release the
  lease.
- Never request global open-PR cleanup. The helper rejects `--prune-open-clean` without both
  `--pr` and `--lease-token`.
- When a merged PR's worktree is removed, delete its local feature branch too — a merged branch
  has no further use, and leaving it behind accumulates stale refs and blocks reusing the name.
- Never remove a dirty or unmerged worktree automatically. Report its path and
  `git status --short --branch`.
- Never remove a worktree protected by another unexpired worker lease or while a worker is still
  running in it — lease-protected removal: hold that PR's worker lease for any per-PR removal.
- Never use raw filesystem deletion for Git worktrees. Use `git worktree remove` through the
  cleanup helper.
- When a PR branch is already checked out in a sibling or foreign dev worktree, `git checkout`
  dead-ends — operate from the assigned worktree in detached HEAD under the head assertion and push
  by refspec rather than sharing the foreign checkout (`safety.md`, Checkout And Push Invariants).

## Commands

Dry run (always safe; lists what would be removed):

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py" --root <worktree-root> --state-dir <state-dir>
```

Queue-only start-of-run cleanup for unleased merged/closed PR worktrees, while the queue lease is
held:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py" --apply --root <worktree-root> --state-dir <state-dir>
```

Scoped cleanup for one merged/closed PR during a single-PR run or queue result, while its worker
lease is held:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py" --pr owner/repo#42 --lease-token <worker-token> --apply --root <worktree-root> --state-dir <state-dir>
```

Scoped cleanup for one clean open-PR worktree after its result is integrated, immediately before
releasing its worker lease:

```text
python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py" --pr owner/repo#42 --lease-token <worker-token> --apply --prune-open-clean --root <worktree-root> --state-dir <state-dir>
```
