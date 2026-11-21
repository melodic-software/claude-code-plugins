---
bump: patch
---

### Changed

- The merge policy reads a pipeline config's keys from one run of the shared YAML parser instead of one `parse-concern-value.sh` run per key, so the post-merge check's walk over the config's history no longer starts thousands of bash processes. Every value, rejection and error is the same as before.
