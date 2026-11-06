---
bump: minor
---

### Added

- `/planning:plan` reads its plan size bands and file-inventory threshold from two new convention-home keys, `plan_size_bands` (`trivial: 1`, `small: 5`, `medium: 15`, each a band's largest file count, rising in that order) and `plan_inventory_min_files` (`10`), in the team `<home>/planning.yaml` and personal `<home>/planning.local.yaml`. With nothing set, the bands and threshold are unchanged.
