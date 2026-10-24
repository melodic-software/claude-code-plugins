---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py lane-room` no longer reports the lane's room unreadable when the run's post-merge answer is past the gate's two-minute reuse age only because a lane merge is still unverified (`unverified-stale`). It keeps the answer when nothing it was read from has moved: main's head, its config commit, the demotion records, and the unverified merges' full and canary runs (`babysit_postmerge.pending_runs_unchanged`, one run listing: none reached a conclusion since, none is past the dispatch deadline, and no quarantine that excused a failing suite has expired). Otherwise it runs the post-merge check again as the gate does (`babysit_merge_policy.lane_room` with the gate's `post_merge`), so a failure found since still refuses. A check that fails or cannot be read leaves the room unreadable, and every other refusal reads as before. `babysit_postmerge.gate_reader` is the one post-merge reader the gate and the room share. The post-merge report now carries `excusesExpireAt`, when the earliest quarantine that excused a failing suite expires.
