---
bump: minor
---

### Added

- babysit-prs: `babysit-postmerge.sh --preflight` runs the merge gate's identity and credential rules alone (the session acts as `merge.agent-identity` and holds no other account) and exits 0 or 2.
- babysit-loop: where the target names a `merge.agent-identity`, the lane launches with that identity's token as its only GitHub credential, and a lane-start identity preflight stops the lane before any write when it refuses. The durable state block carries a `demotion_events` total.

### Changed

- babysit-loop: a merge-eligible pull request merges only through the gate's `--unattended --merge`, never `--auto`; the post-merge check always passes `--remediate`, since the preflight established the identity.
- babysit-prs: "Merge-lane auto-merge" becomes "Merge lane: no auto-merge". A lane-pinned invocation merges only through `--unattended --merge`; otherwise it reports the PR merge-ready for a human. No guidance arms or re-arms auto-merge, and the GitHub arm command is gone.
