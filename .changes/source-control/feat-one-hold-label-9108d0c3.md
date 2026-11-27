---
bump: minor
---

### Changed

- The `do-not-merge` label is the one pull request hold. The babysit merge gates (`babysit_merge.py`, `babysit_merge_policy.py`, `babysit_merge_prefilter.py`, `babysit_whole_review.py`) and the pull-request scripts (`check-ready-holds.sh`, `reassess-limits.sh`, `check-gate-lines.sh`) no longer read body hold phrases, the lanes' hold line or member comments as holds.
- `/source-control:pull-request create --hold` takes no value: it opens the pull request with the `do-not-merge` label (`gh pr create --label do-not-merge`, or a labels write after a REST create or after a `gh pr create` that could not set the label) and leaves it a draft when labeling fails.
- `/source-control:pull-request ready` flips a draft that carries `do-not-merge` and leaves the label on: the label holds the merge, not the flip. `check-ready-holds.sh` reads no labels, label events, comments or trusted-actors list; a WIP title, a `Draft:` line on an unattended run and a closed linked issue still refuse.
