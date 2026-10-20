---
bump: patch
---

### Fixed

- pr-merge's review evidence no longer lets a later clean review of the same head clear a finding an earlier review of that head reported. Each head on the covering chain counts the most summary findings, and the most inline findings left without a thread, that any completed review of it, whole or incremental, reported; a resolved thread closes on a clean covering review only when no such review reported a finding. A finding clears only by a new head (a fix) or a human resolution, so re-running a review until it comes back clean closes nothing ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
