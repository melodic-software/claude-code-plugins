---
bump: patch
---

### Changed

- The babysit merge policy's carry-refusal list adds the formal-verification plugin's `scripts/` and `lib/`, which the `CI Status` job now runs: a push that touches them stops an approval carrying, as for the other code a required check loads.
