---
bump: minor
---

### Added

- `remote/` top-level surface classification in the shared `lib/plugin_cache_versions.py` `SURFACE_TABLE` and stat-only `projects_audit` orphan summary via `lib/claude_projects.py` (`NullTranscriptCwdAdapter`).

### Changed

- `install_state.py` consumes shared `lib/plugin_cache_versions.py` (`resolve_claude_dir`, `SURFACE_TABLE`, `NEVER_READ_GLOBS`, strict UTF-8 `AllowlistGuardedReader` preserving all four read guards, and `classify_cache_relpath`).

### Fixed

- `unreferenced_versions` and `node_modules_bucket` exclude depth-1 `plugins/cache/temp_git_*` staging clones instead of misclassifying nested `.git/objects` directories as plugin versions.
- Invalid UTF-8 bytes in `settings.json` or `installed_plugins.json` now fail closed instead of substituting replacement characters.
