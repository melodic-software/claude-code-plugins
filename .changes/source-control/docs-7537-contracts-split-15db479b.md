---
bump: patch
---

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

### Fixed

- `write-changelog-fragments.sh` writes a fragment for a listed convention whose changelog is at `docs/contracts/<name>/CHANGELOG.md`, as it already did for `docs/conventions/<name>/`.
