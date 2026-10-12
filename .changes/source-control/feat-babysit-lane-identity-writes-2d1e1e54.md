---
bump: minor
---

### Added

- babysit-prs: `babysit-postmerge.sh --preflight` runs the merge gate's identity and credential rules alone (the session acts as `merge.agent-identity` and holds no other account) and exits 0 or 2.
- babysit-loop: where the target names a `merge.agent-identity`, the lane launches with that identity's token as its only GitHub credential, and a lane-start identity preflight stops the lane before any write when it refuses. The durable state block carries a `demotion_events` total.

### Changed

- babysit-loop: a merge-eligible pull request merges only through the gate's `--unattended --merge`, never `--auto`; the post-merge check always passes `--remediate`, since the preflight established the identity.
