---
bump: minor
---

### Added

- `comment_lint_keep_opening`, a team-file list of repository-relative path globs in `comment_lint_exclude`'s syntax: for a matching file the comment lint passes its opening comment block (the comment lines after an optional shebang and any blank or `set -` lines, up to the first other line) and judges every other comment as before. The plugin ships no entries.
