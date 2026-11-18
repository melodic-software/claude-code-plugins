---
bump: patch
---

### Changed

- The `compress_articles` record in the config reference quotes caveman's **Remove** list, so it is a stored value and gets back its as-of date, 2026-11-06.
- `/docs-hygiene:audit-derivability`'s Sources pointer for which subagents skip launch-loaded files no longer carries a recheck trigger, and the matching row is gone from its Recheck triggers table.
