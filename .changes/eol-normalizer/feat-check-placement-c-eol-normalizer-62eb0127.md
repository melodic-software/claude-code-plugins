---
bump: minor
---

### Changed

- The per-edit `PostToolUse` row is replaced by one `PostToolBatch` row that normalizes the line endings of every file a `Write`, `Edit` or `MultiEdit` in the batch named, once, and prints nothing. The "line endings set to LF/CRLF" message and the telemetry envelope are gone. A batch that names no file path costs only the `node` launcher.
- A file that only a `Read` or a shell command named is never rewritten, and a file under `.githooks/` is skipped.
- A missing `jq` now skips silently; `/eol-normalizer:check` reports it.

### Added

- `hooks/eol-git-add.test.sh` records why there is no pre-commit entry: `git add` applies the same `.gitattributes` to the stored bytes, so a commit never carries the wrong ending whether or not this hook ran.
