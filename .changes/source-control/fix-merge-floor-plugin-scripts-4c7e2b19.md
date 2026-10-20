---
bump: patch
---

### Fixed

- `babysit_risk.HIGH_FLOOR` holds `plugins/*/scripts/**` and `plugins/*/skills/*/scripts/**`, the plugin and skill script directories that skills run through `!` lines and agents and workflows run by path. Its `scripts/**` entry matched only the repository root, so a pull request changing only such a script scored LOW.
