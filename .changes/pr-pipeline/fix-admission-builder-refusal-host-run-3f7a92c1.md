---
bump: patch
---

### Fixed

- Admission refusals that say "a builder session takes it" (a protected path the issue lane cannot
  push, or a size-split sub-issue whose patch is over the scan job's cap) now add `host-run` when
  nothing else refuses, waits or holds the issue. They parked at `status: confirmed` with no
  label, so a host or builder session's `host-run` query never found them.
