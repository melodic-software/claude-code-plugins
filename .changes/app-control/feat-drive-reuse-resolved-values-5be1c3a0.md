---
bump: patch
---

### Fixed

- A later rewrite of the report, cleanup's included, scans the public reports with the values the run already resolved instead of resolving the `values:` sources again. A source that resolves only while the app runs no longer leaves every capture `not-checked` after cleanup: each capture keeps its first post-check verdict while its sidecar is unchanged, and a source that cannot resolve again unpublishes only the two public reports.
