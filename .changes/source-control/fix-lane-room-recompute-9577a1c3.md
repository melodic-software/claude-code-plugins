---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py lane-room` no longer reports the lane's room unreadable when the run's post-merge answer is past the gate's two-minute reuse age only because a lane merge is still unverified (`unverified-stale`). It checks again the way the gate does (`babysit_merge_policy.lane_room` with the gate's `post_merge` and `share`), writes the fresh answer back to the `--postmerge-result` file, and uses it, so a failure found since still refuses. A check that fails or cannot be read leaves the room unreadable, and every other refusal reads as before. `babysit_postmerge.gate_reader` is the one post-merge reader the gate and the room share.
