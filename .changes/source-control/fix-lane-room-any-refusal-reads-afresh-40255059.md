---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py lane-room` no longer reports the lane's room unreadable when the gate would not reuse the run's post-merge answer for a reason other than `unverified-stale`: too old, from the future, a demotion record filed or changed since (`demotion-changed`), or a lane merge it does not count (`new-merge:#<n>`). As the gate does, it reads the answer again (`_recompute_shared`, demotion included), so a demotion filed since still holds the rung off and a failure found since still refuses. Only an `unverified-stale` answer may still be kept unchanged when nothing it was read from has moved. With no check to run, or a check that fails or cannot be read, the room stays unreadable.
