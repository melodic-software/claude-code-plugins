---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/verification.yaml`, read from the default branch by `lib/read-verification.sh`. `/verification:confirm` skips its fresh-context verifier under `light` and `off` and gives `NOT VERIFIED` with `verification: skipped (<level>)`; `strict` sends every change to the verifier. `/verification:setup check` reports both keys.
