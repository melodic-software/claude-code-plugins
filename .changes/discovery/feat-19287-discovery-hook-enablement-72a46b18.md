---
bump: minor
---

### Added

- Added the `webfetch_truncation_enabled` per-hook on/off setting (default `true`) in `userConfig` and `docs/conventions/discovery.yaml` for `hooks/webfetch-truncation.mjs`, resolved through `lib/hook-enabled.mjs` with user-over-repository precedence per the hook-enablement convention.
