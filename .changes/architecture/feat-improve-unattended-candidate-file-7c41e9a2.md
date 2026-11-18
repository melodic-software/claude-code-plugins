---
bump: minor
---

### Added

- `/architecture:improve deepening --unattended` asks nothing, renders no page, and writes a candidate file under `<memory_dir>/architecture/improve/<branch-slug>/` whose header records the mode, verification level, threshold, producer and source commit. A security defect appears there only as a `security-defect: withheld` line.
- An `improve` settings object in `architecture.yaml`: `unattended_min_badge` (default `Speculative`, every band), `history_commits` (default 100) and `exclude_authors` (default `["[bot]"]`).

### Changed

- The deepening and conventions lenses read their history window and excluded authors from those settings. The defaults match the values they used before.
