---
bump: patch
---

### Fixed

- work-unblock moves a closed issue's Work status from agent-ready to needs-triage, on the close
  path, the sweep and a finished split parent's close, so a reopened issue no longer reads as
  queued work with no run behind it. A post-merge fix issue and an issue open again keep theirs,
  and any state other than agent-ready stays.
