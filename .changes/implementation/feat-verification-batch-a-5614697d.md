---
bump: minor
---

### Added

- `/implementation:implement` reads the `verification` level at each phase boundary: `light` and `off` skip the fresh-context verifier and write `verification: skipped (<level>)` in the plan mark unless `verify_mechanical_phases` resolves `true`; `strict` turns `verify_mechanical_phases` on.
