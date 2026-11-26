---
bump: minor
---

### Added

- `audit-install-state` reads `managed-settings.d/*.json` drop-in files alongside the base `managed-settings.json` through a dedicated `managed_settings.py` module matching `lib/managed-scope.sh` platform paths.

### Fixed

- `read_retention` merges `cleanupPeriodDays` across base and alphabetical drop-in files (later file wins), withdraws `settings-unparsable-pauses-sweep` when a valid drop-in supplies `cleanupPeriodDays`, and emits `managed-settings-unparsable-refuses-start` on any unparsable base or drop-in file.
