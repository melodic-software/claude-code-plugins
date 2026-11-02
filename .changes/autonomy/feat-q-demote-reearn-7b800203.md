---
bump: minor
---

### Changed

- A demoted promotion cell is promoted again from run evidence, with no person ratifying it again and no binding update. `check-security-binding.mjs` evaluation mode reads a `re-earned` event (`{cell, event: "re-earned", at, since, covers}`) for the cell itself: when its `since` is at or after every contrary event in the cell's epoch, its prerequisites' included, its `at` is at or after `since`, and `covers` equals the count of distinct contrary events against the cell or a prerequisite at or before `since`, the cell resolves effective promoted. A malformed re-earn, or a contrary event with no parsable instant, keeps the cell unpromoted, and a prerequisite's re-earn never revives a dependent.
