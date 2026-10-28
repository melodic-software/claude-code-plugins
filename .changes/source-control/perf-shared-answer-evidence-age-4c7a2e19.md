---
bump: patch
---

### Changed

- The pr-merge gate keeps the run's shared post-merge answer for a candidate past the two-minute unverified age, up to its 30-minute age, when nothing it was read from has moved: main's head, its config commit, the demotion records, and the verifying runs of its unverified lane merges (`babysit_postmerge.pending_runs_unchanged`, the proof the lane room and `settle` already keep it on). The candidate reports `postMergeShared: kept:unverified-stale` and skips its own floor and post-merge check. A verifying run that reached a conclusion since, red or green, a failed or partial run listing, a moved head or config commit, a changed demotion record, a merge past the dispatch deadline or an expired quarantine excuse still reads the answer again (`unused:unverified-stale`). Over 24 scheduled pr-merge runs on 2026-10-27/28, 21 candidates in 10 runs read it again at a median 88 GitHub calls each.
