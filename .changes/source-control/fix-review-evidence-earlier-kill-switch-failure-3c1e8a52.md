---
bump: patch
---

babysit-prs review evidence: a run on an earlier head whose kill-switch job failed before any lane job existed (a setup error, for one) reviewed nothing, so it no longer unbinds the lane with `no-lane-job`; at the pinned head such a run still unbinds.
