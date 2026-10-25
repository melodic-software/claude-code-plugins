---
bump: minor
---

### Added

- The `plugins` sync report's `Divergences:` row names where the skew sits: under the count line, one sub-line per project path gives its diverging record count and up to 3 ids, then `+K more`. The digest's `divergences.records` carries every diverging id with its scope, version and projectPath, and `divergences.by_path` the per-path grouping the sub-lines render. A digest without these fields renders the count line alone.
