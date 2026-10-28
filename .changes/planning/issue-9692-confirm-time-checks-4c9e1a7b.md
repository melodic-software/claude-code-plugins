---
bump: minor
---

### Added

- The interview page's restatement box shows `N of M answers accepted as recommended` before the Confirm. When every answer took the recommendation, it offers "Have agents check these answers", which sends one `accept-audit` event for the accepted questions.
- The restatement box lists the unticked commitments of accepted and own answers. A "Tick these and confirm" button beside Confirm ticks each one, then confirms the understanding. Plain Confirm still ticks nothing.
