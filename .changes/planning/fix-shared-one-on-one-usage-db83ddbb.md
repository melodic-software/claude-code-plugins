---
bump: patch
---

### Fixed

- A one-on-one shared interview (one guest) now records its tap counts: at shutdown the session's `use:`, `rage:` and `dead:` totals are written once with no pid, fingerprint, browser or page view, and its per-page-view pairs are counted as dropped. In a session with two or more guests a batch from one guest is still never written.

### Removed

- The page no longer sends `rep:<fp>` repeat counts, and the server drops any an older page sends, so a usage count can no longer be joined to a fault entry's pid.
