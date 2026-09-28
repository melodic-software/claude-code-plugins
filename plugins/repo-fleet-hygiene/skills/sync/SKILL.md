---
description: "Move each canonical checkout onto the remote default branch and fast-forward it. Bare invocation prints a plan. --apply mutates after one confirmation. Divergent work is parked in a linked worktree. Non-fast-forward, dubious ownership, and a partial stash apply are skipped and reported. Never installs, never resets, never force-pushes."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--repo <dir>]... [--config <file>] [--from-file <file>] [--apply] [--yes] [--park-root <dir>]"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh:*)
metadata:
  workflow-stage: operator
  summary: Fast-forward canonical checkouts onto the remote default branch
  cadence: weekly
---

## Purpose

Put every canonical checkout on the remote's current default branch and fast-forward it. A bare run prints the plan. Mutation is `--apply`, after one confirmation (or `--yes` when no terminal is available).

**Claim:** the default branch is the symref `git ls-remote --symref origin HEAD` prints, and the update is `git pull --ff-only`. Divergent work on another local branch is parked with `worktree-create.sh --existing-branch`. A dirty default branch is parked on a new `park-<timestamp>` branch because that work has no other branch name. Audit's no-scope path uses the same resolver's ghq and cwd rungs, and still does not treat `CLAUDE_PROJECT_DIR` as a repo. **Basis:** [git-ls-remote](https://git-scm.com/docs/git-ls-remote) `--symref` ("In addition to the object pointed by it, show the underlying ref pointed by it when showing a symbolic ref. Currently, upload-pack only shows the symref HEAD, so it will be the only one shown by ls-remote."), fetched 2026-09-28. [git-pull](https://git-scm.com/docs/git-pull) ("`git pull --ff-only` will only do fast-forward updates: it fails if your local branch has diverged from the remote branch."). **As of:** 2026-09-28. **Recheck:** a git release changes `--symref` HEAD output or stops failing a non-fast-forward `--ff-only` pull.

## Scope

The bundled resolver prints repositories from, in order: `--repo`, `fleet.repo` / `fleet.root` in `--config`, `--from-file`, `ghq root` when `ghq` is on PATH, then the git work tree that contains the cwd. No path is exit 3.

## Run

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh" --repo <dir>
bash "${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh" --apply --yes --repo <dir>
```

Pass `--project` paths as `--repo`. Do not run `--apply` unless the user asked to update the checkouts.

## Next

/repo-fleet-hygiene:audit

Audit after the fast-forward when the question is evidence, not the move.

## Gotchas

A skipped repo stays where it was. Read the `result` line. Do not follow a skip with `git reset` or `git push --force`.
