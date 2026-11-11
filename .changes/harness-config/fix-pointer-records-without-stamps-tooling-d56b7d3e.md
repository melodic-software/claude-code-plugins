---
bump: patch
---

### Fixed

- `/harness-config:audit-instructions` I40 no longer marks a bare `#N` in an agent definition whose block also cites N upstream (as `owner/repo#N` or an `/issues/N` or `/pull/N` URL), so a pointer record without an as-of date or recheck trigger can name its upstream bug by number. A block with an as-of date and recheck trigger stays exempt.

### Changed

- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.
