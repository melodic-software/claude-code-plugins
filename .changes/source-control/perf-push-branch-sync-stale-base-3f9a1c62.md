---
bump: minor
---

### Added

- `push-branch.sh` can merge the pull request's base into the branch just before it pushes, when the branch is behind the base and both changed overlapping paths since the merge-base. A push that waited in a rate gate while the base moved is then not refused by a pre-push stale-base check. The base is fetched from the remote that is the PR's base repository; with none, the step is skipped. The overlap rule is the base ref's `scripts/check-stale-base-overlap.sh --check <remote>/<base>` when the base has one, else the paths both sides changed; nothing in the pushed head is run. The merge is `git merge --no-edit`, never a rebase. It is signed when `commit.gpgsign` is true or HEAD is signed. A conflict aborts the merge, pushes nothing and exits 4. The step is off by default. Turn it on with `sync_stale_base: true` in `docs/conventions/source-control.yaml` on the base repository's default branch, or `--sync-stale-base` for one push; `--no-sync-stale-base` turns it off for one push. A lane push never runs it. The `create` and `ready` references describe the new step and exit code.
