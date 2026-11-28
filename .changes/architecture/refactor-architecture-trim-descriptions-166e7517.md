---
bump: patch
---

### Changed

- Backfilled invocation probe sets (`probes/improve-layout.json`, `probes/enforce-boundaries.json`, `probes/principles.json`) and trimmed 14 skill frontmatter descriptions (6,421 -> 4,550 chars across changed skills, -1,871c / -29.1%: `adr` 654 -> 345, `enforce-boundaries` 412 -> 331, `improve` 557 -> 348, `improve-layout` 566 -> 345, `map-components` 403 -> 349, `map-containers` 392 -> 348, `map-context` 352 -> 331, `map-data` 473 -> 348, `map-deployment` 364 -> 339, `map-events` 404 -> 348, `map-flow` 468 -> 349, `map-landscape` 358 -> 300, `principles` 354 -> 338, `setup` 664 -> 131) with zero body changes. Sibling exclusions in the `map-*` descriptions name their targets as fully qualified `/architecture:<skill>` routes, `adr` keeps its skip when no alternative was weighed, and `improve` names its `conventions` lens, with a positive probe for it in `probes/improve.json`.
