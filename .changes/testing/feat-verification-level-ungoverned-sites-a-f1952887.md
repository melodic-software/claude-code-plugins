---
bump: major
---

### Changed

- **Breaking:** `/testing:write` now reads the `verification` level for its HIGH/CRITICAL advisor checkpoint. Under the default `light` (and `off`) it calls no advisor and reports `verification: skipped (<level>)`; `strict` calls it for every suite. Set `verification: standard` (or `verification_skills.write`) in `docs/conventions/testing.yaml` on the default branch to keep the checkpoint.
