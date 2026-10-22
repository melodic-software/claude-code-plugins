---
bump: patch
---

### Fixed

- A one-on-one shared interview (only one guest ever joined) now records its tap counts: at shutdown the session's `use:`, `rage:` and `dead:` totals are written once with no pid, fingerprint, browser or page view, and its per-page-view pairs are counted as dropped. In a session two or more guests joined, a batch from one guest is still never written, even when only one of them sent summaries.

### Removed

- The page no longer sends `rep:<fp>` repeat counts, and the server drops any an older page sends, so a usage count can no longer be joined to a fault entry's pid.
