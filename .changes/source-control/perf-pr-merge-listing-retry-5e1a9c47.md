---
bump: patch
---

### Fixed

- read the artifact listing again after a page body cut short

  gh reports a truncated page as `unexpected end of JSON input`, which the
  verify-evidence reader treated as a permanent failure: the skip step
  skipped nothing and the gate refused with `verify:unreadable` without a
  second read. It is now a transient error: a whole listing cut short is
  read once more, never twice, since each such read may have paged every
  artifact. The incremental listing's page reads
  are read again the same way, and so is a page whose body is cut short
  while gh exits 0, so one bad page no longer costs a whole listing. A
  listing that keeps failing still refuses.
