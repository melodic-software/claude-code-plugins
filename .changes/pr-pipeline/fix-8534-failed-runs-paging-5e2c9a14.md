---
bump: patch
---

### Fixed

- The monitoring lane reads failed runs 100 to a page, up to 5 pages (`LIMITS.failedRunPages`), until it keeps 12 lane runs, so a page full of failing fork or pull-request runs no longer hides a failed run of this repository's own. When 5 full pages keep fewer, the read records a `failed runs` gap, which leaves signal 3's issue as it is.
