---
bump: patch
---

### Added

- The bundled git-hook check library's `checks_file_text` takes `--tip` and, in pre-push mode, reads a path from the tip of the pushed range that changed it; the new `checks_regular_file` reports whether the path is a regular file in the same place.
