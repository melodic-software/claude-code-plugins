---
bump: minor
---

### Added

- `/session-flow:audit-sessions` drift check: the census now counts each `toolDenialKind` value as a `denial_kind:<value>` key, so a denial kind that first appears in the newest Claude Code version is reported as a `new` change in `collect.py drift`. A new expect-absent canary, `invariant:subagent_files_missing`, counts sessions that have no subagent file even though an Agent or Task call returned without an error. A rejected, denied or failed call writes no file, so it does not count. It feeds `subagents.count`, which no longer shows as unchecked for lack of a canary.
