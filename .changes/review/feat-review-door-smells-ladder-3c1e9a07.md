---
bump: minor
---

### Changed

- The shared door definition (`reference/one-way-doors.md`) rates migrations by its own test: one
  that rewrites, deletes or narrows existing data or structure is a one-way door; an additive one
  is a two-way door while the previous code still runs against the new schema, and removing the
  added structure is a separate change; turning a feature off after users wrote data through it is
  a one-way door. `/review:merge-risk` no longer rates every applied migration `HIGH` under
  Reversibility.
- `/review:merge-risk`'s Impact area gains a `HIGH` floor for a migration whose run can lock,
  rewrite or backfill a large or busy table: the cost of running it, rated apart from whether it
  can be undone.
