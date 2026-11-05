---
bump: patch
---

### Fixed

- Four eval cases (`fix-handles-legitimate-missing-coupon` and the three `phase6-*` cases) load again: six of their graders set `focus: reply`, which `claude plugin eval` rejects, so the cases were skipped without a run. They now set `focus: last_message`.
