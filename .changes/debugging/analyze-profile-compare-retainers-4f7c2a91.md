---
bump: minor
---

### Added

- `/debugging:analyze-profile`'s `query_profile.py` gains two read-only subcommands for converted heap snapshots: `compare <before.db> <after.db>` lists which heap types grew between two snapshots, and `retainers <db> <idx>` prints the shortest non-weak path from the root to one heap object.
