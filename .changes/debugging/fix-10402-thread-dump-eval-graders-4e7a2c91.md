---
bump: patch
---

### Fixed

- The `analyze-profile-reads-thread-dump` plugin eval case drops its `names-a-second-dump` regex, which passed "another thread holds in this dump" and missed "take two dumps" and "run it again". Its `names-the-cycle` judge now also requires a later dump as the capture that would settle the cause, with samples for each wording.

### Added

- A `no-file-edited` grader on the same case fails a Bash call that edits a file in place, redirects into a file, or copies, moves, deletes, patches or git-restores one, with samples written as Bash tool input.
