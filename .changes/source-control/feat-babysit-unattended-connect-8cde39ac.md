---
bump: minor
---

### Added

- babysit-prs: the merge gate's `--unattended` path is connected. With `merge.authority: local-babysit` and a `merge.agent-identity` in the repository's `pr-pipeline.yaml` (read at the pull request's base SHA), it decides in the wiring order (identity, a `gh auth status` chokepoint that refuses any other listed account, the kill switch, the post-merge check, demotion and cap, one merge in flight, promotion evidence from managed or executor-owned settings, eligibility, review evidence bound to the head, the diff score) and, with `--merge`, enqueues a LOW pull request at its pinned head after a pin comment, writes one upserted reasons comment for MED or HIGH, disarms an armed auto-merge, dequeues on a stop or a hold, and dispatches the full run once the entry reads back merged. New `--promotion-settings`; `--allow-unpinned-head`, `--stacked-prs` and an unpinned merge are refused under `--unattended`.
- babysit-prs: `babysit-postmerge.sh` exits 5 while an auto-merge is not yet verified, reads each identity merge's pinned head from its pin comment, and defaults `--since` to the merge gate's floor (the enabling config commit, or the newest human close of a demotion record).

### Changed

- babysit-prs: the merge gate and the post-merge check share one auto-merge derivation, and a merge that bypassed the queue counts as an auto-merge unless a human merged it. Eligibility refuses a work-class label applied through an App or removed by a non-human. Review evidence unbinds on a retargeted base or a reviewed head whose run is gone, instead of undercounting.
