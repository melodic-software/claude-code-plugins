---
bump: minor
---

### Added

- A `transcript_sources_file` option names a JSON file of transcript sources: Claude Code configuration directories on this host and on hosts reached over ssh. Unset, only this host's configuration directory is read.

### Changed

- `/harness-ops:audit-performance`, `/harness-ops:audit-skill-visibility --installed` and `/harness-ops:inventory` take `--sources-file` and read the first local source's configuration directory (unset, `CLAUDE_CONFIG_DIR`, else `~/.claude`). Each report's `header` names a local source whose projects directory cannot be listed, with the command that retries it, and `--diagnostics-dir` keeps it as a lookup diagnostics record.
- A `transcript_sources_file` path, and a local source's `config_dir` in it, starting with `~` are read from the home directory; a missing sources file prints its warning once per run.
- `/harness-ops:inventory` reads `.claude.json` inside a configuration directory taken from the sources file, as it does for `--config-dir` and `CLAUDE_CONFIG_DIR`, unless that directory is `~/.claude`.
