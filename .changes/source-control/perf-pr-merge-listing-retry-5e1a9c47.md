---
bump: patch
---

### Fixed

- read the artifact listing again after a page body cut short

  gh reports a truncated page as `unexpected end of JSON input`, which the
  verify-evidence reader treated as a permanent failure: the skip step
  skipped nothing and the gate refused with `verify:unreadable` without a
  second read. It is now a transient error, read again within the
  listing's shared timeout like a 5xx. The incremental listing's page reads
  are read again the same way, and so is a page whose body is cut short
  while gh exits 0, so one bad page no longer costs a whole listing. A read
  that keeps failing still refuses after three reads.
