---
bump: patch
---

### Fixed

- The pr-unblock dispatcher (`pr-unblock-dispatch.yml`) dispatches resolve-conflicts again for a conflicting pull request whose head a select job stopped on (`Skipped: lane-stopped`, such as `unresolved-conflict`) once main has moved: that stop now counts only while the base tip was committed before it started, and the dispatch record keeps such a head with the base tip it was judged against, so a run reads it again only after main moves. A head with an unchanged base stays skipped, a finished run, a slot skip or the per-head cap still ends the head, and heads retried on a moved base go after heads never tried. The record moves to version 5, so the first run after this change reads every head once.
