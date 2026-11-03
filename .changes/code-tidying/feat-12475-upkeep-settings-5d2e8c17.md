---
bump: minor
---

### Added

- Upkeep settings `upkeep_cadence`, `upkeep_backstop` and `upkeep_max_open` in
  `<home>/code-tidying.yaml` (defaults `daily`, `weekly`, 3), read by
  `skills/tidy/scripts/upkeep-setting.sh`. See `reference/config.md`.

### Changed

- The `/code-tidying:tidy` backlog throttle takes its limit from `upkeep_max_open`, and
  `open-pr-count.sh` reports the limit and the layer that supplied it.
