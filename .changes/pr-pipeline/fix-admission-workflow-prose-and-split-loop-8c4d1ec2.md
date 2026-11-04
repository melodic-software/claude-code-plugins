---
bump: patch
---

### Fixed

- A size-split sub-issue whose run's patch the scan job refused for its size
  (`scan-refused-patch`) is no longer re-admitted unchanged into the same stop. A sub-issue never
  splits again (owner Q93), so admission skipped the split park and admitted it, and the triage
  sweep looped it until its run limit handed it to a maintainer. Admission now refuses it with
  no hold, at `status: confirmed`, for a builder session.
