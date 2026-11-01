---
bump: minor
---

### Added

- work: a bug path for bug items (#11865). The run names the broken and expected final states before any run, reproduces the bug twice through the real surface from a reset, and runs verify-existing-fix when a fix may already exist: the baseline reproduces twice and the patched build resolves it twice, ending Confirmed, Insufficient fix or Inconclusive, and never opening a competing PR. It writes the failing test first when a cheap local target exists, opens a draft PR only with before-and-after proof (the same path run twice on the patched build), and never merges. Two eval cases cover a confirmed reproduction and an already-fixed item.
