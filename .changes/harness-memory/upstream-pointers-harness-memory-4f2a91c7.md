---
bump: patch
---

### Fixed

- `/harness-memory:audit` no longer prices a move into a skill as losing its body after compaction: the compaction model now records that recently invoked skill bodies come back within a budget, and points at the docs section that owns the caps.

### Changed

- The audit and stateless references point at the exact live docs sections for upstream specifics (import depth, `claudeMdExcludes`, rule loading, auto-memory load limits and storage, settings precedence, managed-settings locations, retention and `claude purge`) instead of restating them, each with an as-of date and a recheck trigger.
