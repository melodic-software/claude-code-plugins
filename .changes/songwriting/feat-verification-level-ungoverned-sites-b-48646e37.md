---
bump: major
---

### Changed

- **Breaking:** `/songwriting:co-write` and `/songwriting:diagnose` now read the `verification` level (`lib/read-verification.sh`, new team file `<home>/songwriting.yaml`, schema `schemas/songwriting.schema.json`). At the default `light`, and at `off`, the hard gate's skeptic refutation row is skipped and named `verification: skipped (<level>)`; `standard` keeps it skippable by the writer's named reason, and `strict` runs it on every batch. The rubric's counted passes run at every level.
