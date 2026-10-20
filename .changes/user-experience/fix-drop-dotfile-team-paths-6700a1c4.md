---
bump: patch
---

### Fixed

- Team settings now drop a `research_paths`, `persona_paths` or `output_home` entry whose first path segment starts with a dot (`.env`, `.aws/credentials`, `.ssh/x`, `.claude-notes/ux`), as written and through symlinks, with a warning. `.claude` and `.git` stay dropped.

### Changed

- The plugin moves to changelog-fragment releases.
