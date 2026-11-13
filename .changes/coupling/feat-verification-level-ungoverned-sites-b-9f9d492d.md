---
bump: minor
---

### Changed

- **Breaking:** `/coupling:reduce` now reads the `verification` level (`lib/read-verification.sh`, new team file `<home>/coupling.yaml`, schema `schemas/coupling.schema.json`). At the default `light`, and at `off`, phase C reproduces nothing: findings are ledgered with `evidence-verified: false`, labeled `unverified`, and kept out of the apply lane, so no reduction is edited or committed. Phase F's build, test and lint run at every level. Set `verification: standard` to restore the reproduction and the apply lane.
