---
bump: patch
---

### Fixed

- pr-merge's review evidence no longer lets a later clean review of the same head clear a finding an earlier review of that head reported: a resolved thread closes on a clean covering review only when no completed review, whole or incremental, of a head on the covering chain reported a finding. A finding clears only by a new head (a fix) or a human resolution, so re-running a review until it comes back clean closes nothing ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
