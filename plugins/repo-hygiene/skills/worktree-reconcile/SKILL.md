---
description: "Dry-run inventory of linked git worktrees and stashes. Prints a Proposed label per worktree (hold-dirty, hold-locked, hold-main, hold-open-pr, hold-carve-out, hold-sha-mismatch, hold-no-merged-pr, review-remove) and never deletes a worktree, branch, stash, or file. review-remove requires a clean tree, a MERGED pull request, and a HEAD that matches the remote tip, because squash-merge makes merge-base --is-ancestor unusable. Use when: 'reconcile worktrees', 'which worktrees are dirty', 'worktree fleet report', 'dry-run worktree cleanup'."
user-invocable: true
disable-model-invocation: false
argument-hint: "[--repo DIR] [--hold SUBSTR]..."
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/worktree-reconcile.sh:*)
---

# Worktree reconcile (dry-run)

Inventory linked worktrees and stashes. Propose an action. Do not perform it.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-reconcile.sh" [--repo DIR] [--hold SUBSTR]...
```

Read `Proposed:` and `Reason:`. `review-remove` means the evidence says the
worktree holds exactly a merged pull request's tip and the tree is clean. It is
not permission to delete, and this skill has no delete command. Anything else
is a hold: dirty work, a lock, `main`, an open pull request, a `--hold`
substring, a SHA that does not match origin, or a missing pull-request row.

`PRDataUnavailable:` means the pull-request map did not run. Do not treat those
rows as safe.

Stashes print `Proposed: inspect-before-prune`. Leave them.

## Next

- After a person confirms a `review-remove` row and wants branch cleanup: `/repo-hygiene:clean git`.

## Gotchas

- Do not use `git merge-base --is-ancestor origin/main <branch>` on a squash-merge
  repository. The merged commits are not ancestors of `main`.
- Pass `--hold` for paths that must survive even when they look unused. The
  script does not know a machine's carve-outs.
