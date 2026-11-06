---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `docs/conventions/docs-hygiene.yaml`, read from the default branch by `lib/read-verification.sh`. `/docs-hygiene:compress` skips the semantic-diff subagent under `light` and `off`; `/docs-hygiene:audit-derivability` skips its spot-tests (verdicts stay provisional) and under `strict` spot-tests every deletion; `/docs-hygiene:audit-noise` skips its verification pass, and under `strict` runs it at every corpus size.
