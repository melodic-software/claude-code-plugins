---
bump: minor
---

### Added

- `/work-items:work` ranks the candidates in each selection tier by their `priority:` label, highest first, and keeps the tier's own order (`next_due`, the guardrails preference, or oldest-first) only as the tie-break, and the work-loop lane ranks its admitted items the same way before its `created_at` order, so a priority raised at triage now changes what a lane picks. The rank comes from the new `work_priority_order` key in the repository's `docs/conventions/work-items.yaml` (default `priority: critical`, `high`, `medium`, `low`); an item with no listed label ranks last in its tier.
