---
bump: patch
---

### Fixed

- `parse-concern-value.sh --strict` now exits 3 when a mapping repeats a key, as the CI config parser does; the shared awk YAML reader took the first value. Non-strict calls are unchanged.
