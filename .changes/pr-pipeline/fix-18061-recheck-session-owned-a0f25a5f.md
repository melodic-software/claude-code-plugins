---
bump: patch
---

### Fixed

- The issue lane's in-slot re-check (`check-blockers.mjs` with `RECHECK=true`) now reads the issue before its blocked_by list, so a session-owned, container or wayfind label, or a `provenance: untrusted` label, added while the run waited for its slot stops the run as admission does. Before, an empty blocked_by list let the run proceed without looking at the issue's labels.
