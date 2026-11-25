---
bump: patch
---

### Changed

- `babysit-prs` `CARRY_REFUSES` adds the work-items triage skill's `scripts/` and `schemas/`, which the intake lane's workflow now loads, so a push that touches one stops an approval carrying, as `merge-holds.mjs` does.
