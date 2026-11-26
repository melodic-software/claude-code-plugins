---
bump: minor
---

### Added

- Standalone read-only JSONL CLI in `deep_inventory.py` (`TARGET [--deep|--shallow] [--out PATH] [--claude-dir PATH] [--no-claude] [--no-validate]`) requiring no `--data-root` and writing nothing to disk by default.
- Injectable `EntryClassifierPort` adapters (`ClaudeHarnessClassifier`, `TmpProducerClassifier`, `SupersededVersionClassifier`, `DanglingSymlinkClassifier`, `DictClassifierAdapter`) and strictly read-only `VersionLivenessPort` (`/proc` + `/proc/locks` inode lock matching and `InMemoryLivenessAdapter`).

### Changed

- `deep_inventory.py` computes mount-safe and `st_dev`-safe sizes in a single pass, classifies subpath targets (`~/.claude/projects`, `~/.claude/plugins/cache`), honors `CLAUDE_CONFIG_DIR`, indexes `launcher_dirs` once per walk, separates depth-1 `plugins/cache/temp_git_*` directories from plugin versions, and resolves `projects/` slugs via the shared cached `lib/claude_projects.py` module.

### Fixed

- `hygiene.py inventory` no longer calls `close_clean_runs()`, keeping read-only inventory from mutating `clean-runs/` markers.
