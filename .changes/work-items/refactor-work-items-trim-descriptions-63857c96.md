---
bump: patch
---

### Changed

- Backfilled 20-query invocation probe `plugins/work-items/probes/measure-delivery.json` and trimmed frontmatter `description` fields across all 12 `work-items` skills to cut ambient listing budget by 2,550 chars (`6,433 -> 3,883`, `-39.6%`; `attend-queue` `587 -> 341`, `decompose` `485 -> 343`, `measure-delivery` `430 -> 336`, `morning-brief` `680 -> 343`, `onboard-adapter` `494 -> 349`, `scan-todos` `405 -> 329`, `setup` `1,000 -> 138`, `ship` `457 -> 344`, `track` `474 -> 348`, `triage` `520 -> 336`, `work-loop` `480 -> 346`, `work` `421 -> 330`) while keeping `disable-model-invocation: true` trigger-free on `setup` and preserving read-only, never-merge, and safety boundaries.
