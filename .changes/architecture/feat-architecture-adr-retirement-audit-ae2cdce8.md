---
bump: minor
---

### Added

- `record-decision` retires the record a new decision reverses, after your yes. The new
  `adr_retirement` setting picks how: `delete` (default; the number is never reused, and the ADR
  folder gets one line saying retired records live in its git history), `supersede` (in the
  repository's own status words) or `archive`. It resolves through all four layers and is reported
  with its layer.
- `/architecture:record-decision audit`: read-only. Lists retire candidates grouped by reason (what
  the record decided is gone from the code, a later commit or record contradicts it, or it fails the
  admission test), each with `file:line` or commit evidence.
- The admission test's "at least one" list gains decisions not discoverable from the code:
  infrastructure, cloud or external services, or a decision not to do something.

### Changed

- The next ADR number counts records in the archive folder and in the folder's git history, so a
  retired number is never reused.
- A record, and any retirement, is committed in the pull request of the change that made the
  decision; a decision with no code change gets its own pull request.
