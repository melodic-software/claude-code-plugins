---
bump: minor
---

### Added

- `inventory.py --skills-index` prints a JSON array with one record per skill: installed plugin skills from the plugin cache, skills of not-installed relative-path plugins from the marketplace checkout, one plugin-level row for each not-installed remote-source plugin, and personal and project skills. Each record carries `plugin`, `skill`, `name`, `description`, `when_to_use`, `state` (`enabled`, `disabled` or `not-installed`) and `source`. `--exclude disabled,not-installed` drops records in those states.
