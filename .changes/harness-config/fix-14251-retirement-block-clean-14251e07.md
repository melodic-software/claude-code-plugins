---
bump: patch
---

### Changed

- Shared `check-retirements.sh` synced where this plugin carries it ([#14251](https://github.com/melodic-software/claude-code-plugins/issues/14251)): it accepts a `block` record kind, which cleans one YAML key and its indented value instead of the whole file; the helper's test suite covers it. No other change to this plugin.
