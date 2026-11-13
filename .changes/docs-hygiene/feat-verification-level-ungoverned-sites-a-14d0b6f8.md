---
bump: major
---

### Changed

- **Breaking:** `/docs-hygiene:extract-ssot` now reads the `verification` level, and under the default `light` (and `off`) skips the adversarial-review round for a `WARN-borderline` cluster, recording `verification: skipped (<level>)` in the working notes. Set `verification: standard` (or `verification_skills.extract-ssot`) in `docs/conventions/docs-hygiene.yaml` on the default branch to keep the round.
