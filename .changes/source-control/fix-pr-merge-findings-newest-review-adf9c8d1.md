---
bump: patch
---

### Fixed

- pr-merge's open-findings count takes summary findings only from the review chain covering the pull request's current head, so a superseded review or an older run at the same head no longer keeps its findings open, and a thread an agent resolved closes once that covering chain reports no finding. Resolving a thread alone, or a clean review of another head, still closes nothing.
