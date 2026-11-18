---
bump: minor
---

### Changed

- pr-merge's merge job reads through the lanes App's installation allowance instead of the repository's shared `GITHUB_TOKEN` pool (owner decision D398). `lane-rules.json` gives the `merge-pr` grant `actions: read`, which the token broker allows to that activity alone. The candidate listing, the carried artifact reads (cursor, head-ref map, verdict reads, lane records), the post-merge check, the skip filter, the gate's verdict and review-evidence reads and the sweep-count read use the lane token, named `lanes-app` to the rate guard. Commit-status reads, the who and superseded reads before the mint, and the re-fire and escalation-clear steps stay on `GITHUB_TOKEN`. No read moves to the other token when its own pool runs low.
