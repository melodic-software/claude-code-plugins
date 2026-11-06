---
bump: minor
---

### Added

- plugins `reset-refresh.sh clean`: a reset level that also discards `data/`, keeping one `~/.claude/plugins.bak-<ts>` backup it never deletes. It runs only from a terminal and refuses while an earlier backup exists. It asks before an install that displays a marketplace-declared command, then accepts it by sha256, never with `-y`. On any CLI failure, snapshot difference or settings-file `cmp` difference, it moves the backup back. `preview` also reports what `clean` would discard.
