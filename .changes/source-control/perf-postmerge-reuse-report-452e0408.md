---
bump: patch
---

### Changed

- `babysit_merge_policy.settle_shared` holds the lane room's reuse rule for a run's post-merge report (`shared_refusal`, keeping an `unverified-stale` answer nothing moved since and a `demotion-changed` one whose demotion reads the same), and `lane_room` calls it. `babysit_verify_evidence.py settle` applies that rule without reading the report again: exit 0 when it stands, 1 otherwise.
