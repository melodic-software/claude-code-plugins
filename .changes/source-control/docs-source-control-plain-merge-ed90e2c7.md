---
bump: patch
---

### Changed

- `pull-request merge` merges with plain `gh pr merge <N> -R <owner>/<repo>` and the flags the repository needs (`--squash`, `--auto` on a merge-queue or auto-merge base, `--admin` only where a code-owner review or merge queue blocks an otherwise ready merge and the consumer's policy allows it), in place of the guarded one-command shape the merge script printed. `--match-head-commit` is optional for an immediate merge and required with `--auto`, so an armed auto-merge cannot merge a later push. A merge GitHub or the permission layer refuses is reported and the session moves on: it is never handed to the user as a command, and never retried in another shape. The babysit merge gate is unchanged.
