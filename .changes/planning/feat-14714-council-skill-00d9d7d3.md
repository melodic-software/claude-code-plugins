---
bump: minor
---

### Added

- **`setup --check` validates list keys.** A list key and its items are checked against the schema (type, length, required keys, allowed keys, patterns, key names) instead of being reported unchecked; a list key using a keyword the checker does not implement stays reported as unchecked. List keys are never written from the command line.
