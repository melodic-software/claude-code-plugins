---
bump: patch
---

### Changed

- Backfilled invocation probe sets (`probes/improve-layout.json`, `probes/enforce-boundaries.json`, `probes/principles.json`) and trimmed 14 skill frontmatter descriptions (6,421 -> 4,543 chars across changed skills, -1,878c / -29.2%: `adr` 654 -> 343, `enforce-boundaries` 412 -> 331, `improve` 557 -> 343, `improve-layout` 566 -> 345, `map-components` 403 -> 350, `map-containers` 392 -> 349, `map-context` 352 -> 331, `map-data` 473 -> 348, `map-deployment` 364 -> 339, `map-events` 404 -> 349, `map-flow` 468 -> 346, `map-landscape` 358 -> 300, `principles` 354 -> 338, `setup` 664 -> 131) with zero body changes and zero probe trigger-rate regressions.
