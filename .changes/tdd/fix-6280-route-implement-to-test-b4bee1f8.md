---
bump: patch
---

### Fixed

- **Implement routes to the Test stage before review.** `/implementation:implement` and `/implementation:implement-dispatch` now name the Test-stage skills in `## Next` (`/testing:plan`, `/testing:audit`, `/testing:run-e2e`), with `/review:quality-gate` once tests are planned, checked and green; the `testing`, `tdd` and `mutation-testing` skills that hand off name their successors too, so the graph runs implement, test, review, verify.
