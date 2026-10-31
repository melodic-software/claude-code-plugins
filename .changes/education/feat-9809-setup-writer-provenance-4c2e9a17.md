---
bump: minor
---

### Added

- `setup` now records `written_against` and a per-key `provenance:` map in the settings file it
  writes. `apply` takes `--default <key>` for a value left at the plugin default. When the plugin
  changes a default, `check` lists it, and a write updates a `default` value and keeps a `chosen`
  one. The schema declares both keys.

### Changed

- An older version of this plugin cannot read a settings file that holds these keys: its `check`
  exits 1 with no PASS line, its `apply` refuses the file, and skills reading a setting through
  `check` drop the whole repository layer. Update everyone sharing a repository before anyone
  writes the file.
