---
description: "Dry-run inventory of linked git worktrees, stashes, and the six filed drive-root stray names. Prints a Proposed label and never deletes a worktree, branch, stash, directory, or file. review-remove requires a clean tree, a MERGED pull request, and a HEAD that matches the remote tip, because squash-merge makes merge-base --is-ancestor unusable. Drive-root names are host-specific: pass --drive-root to scan one directory. Use when: 'reconcile worktrees', 'which worktrees are dirty', 'D: root strays', 'dry-run worktree cleanup'."
user-invocable: true
disable-model-invocation: false
argument-hint: "[--repo DIR] [--hold SUBSTR]... [--drive-root DIR]"
metadata:
  workflow-stage: anytime
  summary: Inventory worktrees and filed drive-root strays; print proposed actions
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/worktree-reconcile.sh:*)
---

# Worktree reconcile (dry-run)

Inventory linked worktrees and stashes. Propose an action. Do not perform it.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree-reconcile.sh" [--repo DIR] [--hold SUBSTR]... [--drive-root DIR]
```

Read `Proposed:` and `Reason:`. `review-remove` means the evidence says the
worktree holds exactly a merged pull request's tip and the tree is clean. It is
not permission to delete, and this skill has no delete command. Anything else
is a hold: dirty work, a lock, `main`, an open pull request, a `--hold`
substring, a SHA that does not match origin, or a missing pull-request row.

`PRDataUnavailable:` means the pull-request map did not run. Do not treat those
rows as safe.

The primary worktree is always `hold-primary`. Built-in carve-outs (`_vfy`,
`ccp-2840-fix`, `ccp-2840`, `silent-revert-markers`, `spike`, `ccp-2590-engine`,
and the branches `fix/2648-tzdata-degradation`, `fix-2618-belt-run-scoped-lifetime`,
and `*-main`) are `hold-carve-out` without `--hold`. `--apply` exits 2.

Stashes print `Proposed: inspect-before-prune`. Leave them.

## Drive-root strays

The same report prints six directory names that are not git worktrees. With no
`--drive-root`, `Present:` is `not-scanned` and `Proposed:` is the filed action.
`--drive-root DIR` reports whether each name is a directory under `DIR` and a
top-level entry count. It does not list other names in that directory, and it
does not delete anything. There is no delete flag.

**Claim:** The six names and actions are the table in issue #2931.
`lane-j-mut-base` and `lane-j-mut-mainbase` are `review-delete`.
`lane-v157-ext`, `lane-v159-mut`, and `lane-v159-repro` are `hold-until-verdict`.
`spike` is `hold-operator-deliverable`. The directory that holds them is
specific to that host, so this skill does not assume a drive letter.

**Basis:** <https://github.com/melodic-software/claude-code-plugins/issues/2931>
(section "Six D:\\ root strays").

**As of:** 2026-09-28.

**Recheck:** that issue's stray table changes, or a `--drive-root` scan on the
host shows a filed name whose presence no longer matches the action a person
intends. On firing, update the table in `scripts/worktree-reconcile.sh` and
this record together.

## Next

- After a person confirms a `review-remove` row and wants branch cleanup: `/repo-hygiene:clean git`.

## Gotchas

- Do not use `git merge-base --is-ancestor origin/main <branch>` on a squash-merge
  repository. The merged commits are not ancestors of `main`.
- Pass `--hold` for paths that must survive even when they look unused and are
  not in the built-in carve-out list.
