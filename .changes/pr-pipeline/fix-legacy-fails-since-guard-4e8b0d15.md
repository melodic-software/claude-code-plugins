---
bump: patch
---

### Fixed

- `upload-fail-index` reads the run's artifacts up to three times, 5 s then 10 s apart, before failing on a read that fails or misses its own count, so one transient API error no longer leaves a FAIL judgment with no verdict. Every other check is unchanged.
