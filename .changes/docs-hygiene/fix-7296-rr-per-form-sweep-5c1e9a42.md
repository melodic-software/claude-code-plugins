---
bump: patch
---

### Fixed

- `/docs-hygiene:rename-references` now states at the pattern-library pointer, in the audit survey and in Blast that the sweep is one Grep call per form it sweeps, never one alternation or a single token grep, so audit runs no longer skip the hidden forms (#7296).
- `/docs-hygiene:rename-references` now treats a released changelog entry as a frozen record and reports frozen hits on one "Kept as history" line, never as a choice for the user (#7296).
