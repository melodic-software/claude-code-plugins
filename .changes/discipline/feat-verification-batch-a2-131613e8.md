---
bump: minor
---

### Added

- A `verification` level and per-skill `verification_skills` in `docs/conventions/discipline.yaml`, read from the default branch by `lib/read-verification.sh`. Under `light` and `off`, `/discipline:do-your-research`, `/discipline:recheck-against-upstream` and `/discipline:sweep-all` skip the fresh-context re-derivation and the fan-out dispatch; under `strict`, do-your-research takes the fan-out tier at `full` depth outside a batch or fork.
