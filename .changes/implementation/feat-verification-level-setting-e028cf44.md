---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/implementation.yaml`, read from the default branch by `lib/read-verification.sh`. `/implementation:implement-dispatch` skips the phase verifier and the post-phase commit verifier under `light` and `off`, writing `verification: skipped (<level>)`, unless `verify_mechanical_phases` resolves `true`; `strict` turns `verify_mechanical_phases` on.
