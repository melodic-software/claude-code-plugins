---
bump: patch
---

### Fixed

- pr-merge's open-findings count takes summary findings only from the review chain covering the pull request's current head, so a review of an earlier head outside that chain no longer keeps its findings open; whole reviews re-run at one head keep the most findings any of them reported. A thread an agent resolved closes once that chain reports no finding and the thread predates the covering review. Resolving a thread alone, or a clean review of another head, still closes nothing.
