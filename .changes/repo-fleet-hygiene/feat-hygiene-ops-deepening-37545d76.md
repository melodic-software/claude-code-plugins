---
bump: patch
---

### Changed

- `audit-fleet.sh`, `sync-fleet.sh`, and `setup-config.sh` share one config-resolution ladder in `scripts/fleet-discovery.sh` (`fleet_resolve_config`, `fleet_clean_project_dir`, `fleet_default_config_path`).

### Fixed

- `sync-fleet.sh` now honors `USERPROFILE` when `HOME` is unset, strips literal `${...}` project-dir placeholders, and fails closed on malformed Git config syntax.
- `setup-config.sh` strips literal `${...}` placeholders from `CLAUDE_PROJECT_DIR` before computing the default config path.
