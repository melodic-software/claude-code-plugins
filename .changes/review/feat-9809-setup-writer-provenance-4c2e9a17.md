---
bump: minor
---

### Added

- `setup` now records `written_against` and a per-key `provenance:` map in the settings file it
  writes. `apply` takes `--default <key>` for a value left at the plugin default. When the plugin
  changes a default, `check` lists it, and a write updates a `default` value and keeps a `chosen`
  one. The schema declares both keys.
- Two eval cases check that `setup apply` passes a key the operator accepts at the plugin default as
  `--default <key>`, and a value the operator chose as `<key>=<value>` even when it equals the
  default, and that the written file records `default` or `chosen` to match.

### Changed

- An older version of this plugin cannot read a settings file that holds these keys: its `check`
  exits 1 with no PASS line, its `apply` refuses the file, and skills reading a setting through
  `check` drop the whole repository layer, so `ratchet_offer`, `downstream_probe` and `fanout_diversity` fall back to their defaults for that session. Update everyone sharing a repository before anyone
  writes the file.
