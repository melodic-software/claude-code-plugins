---
bump: minor
---

### Changed

- The `do-not-merge` label is the one pull request hold. The babysit merge gates (`babysit_merge.py`, `babysit_merge_policy.py`, `babysit_merge_prefilter.py`, `babysit_whole_review.py`) and the pull-request scripts (`check-ready-holds.sh`, `reassess-limits.sh`, `check-gate-lines.sh`) no longer read body hold phrases, the lanes' hold line or member comments as holds.
- `/source-control:pull-request create --hold` takes no value: it opens the pull request with the `do-not-merge` label (`gh pr create --label do-not-merge`, or a labels write after a REST create) and leaves it a draft when labeling fails.
