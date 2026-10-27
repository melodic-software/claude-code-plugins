---
bump: minor
---

### Added

- `push-branch.sh` can merge the pull request's base into the branch just before it pushes, when the branch is behind the base and both changed overlapping paths since the merge-base. A push that waited in a rate gate while the base moved is then not refused by a pre-push stale-base check. The overlap rule is the checkout's `scripts/check-stale-base-overlap.sh --check <remote>/<base>` when the file exists, else the paths both sides changed. The merge is `git merge --no-edit`, never a rebase. It is signed when `commit.gpgsign` is true or HEAD is signed. A conflict aborts the merge, pushes nothing and exits 4. The step is off by default. Turn it on with `sync_stale_base: true` in `docs/conventions/source-control.yaml`, or `--sync-stale-base` for one push; `--no-sync-stale-base` turns it off for one push. A lane push never runs it. The `create` and `ready` references describe the new step and exit code.
