---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` binds a review lane's second attempt after a kill switch stopped the first: the caller's `kill-switch` job succeeded and wrote its lane's `a kill switch stops this review (` or `security review (` notice, and the first attempt has no lane job, so the review never started. ci-status tells a person to re-run such a run once the switch is off, and that re-run was refused as `rerun-not-allowed`. A kill-switched run on an earlier head also no longer unbinds the lane as `no-lane-job`. The lane-run collector reads the kill-switch job's annotations only for an attempt with no lane job. The merge gate does not start this re-run, because it cannot read the switch.
