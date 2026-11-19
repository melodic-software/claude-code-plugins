---
bump: patch
---

### Fixed

- `save_point.py validate` no longer lets a successor drop a carried rule, decision or question
  because its predecessor failed only on size: handoffs written from now on carry a `checks: 2`
  stamp, and for them the predecessor downgrade applies only to content failures. Older files
  validate as before.
