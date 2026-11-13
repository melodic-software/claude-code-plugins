---
bump: minor
---

### Changed

- **Breaking:** `/plugin-quality:audit`'s adversarial re-examination seam now reads the `verification` level (`lib/read-verification.sh`, new team file `<home>/plugin-quality.yaml`, schema `schemas/plugin-quality.schema.json`). `standard` keeps its `high`-effort gate and `strict` runs it at every effort. At the default `light`, and at `off`, it runs at no effort, and the emitted item says `verification: skipped (<level>)` and labels each finding `unverified`. Set `verification: standard` to restore the seam.
