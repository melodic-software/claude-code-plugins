---
bump: major
---

### Changed

- **Breaking:** `/knowledge:docpage-digest` now reads the `verification` level on the single-page path. Under the default `light` (and `off`) Phase 4 dispatches neither verifier arm: the pin and the standing gates still run, Phase 4 is ticked with `verification: skipped (<level>)`, and the checklist and handoff carry `unverified: verification: skipped (<level>)`. Set `verification: standard` (or `verification_skills.docpage-digest`) in `<home>/knowledge.yaml` on the default branch to keep both arms. The batch workflow still runs both arms at every level.
- The map-corpus inventory format no longer names a verifier for rationale quality; none runs.
