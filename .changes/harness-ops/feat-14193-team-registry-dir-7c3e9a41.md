---
bump: minor
---

### Added

- A repository can set the known-issues registry directory for everyone who works in it: `registry_dir` in `harness-ops.yaml` in its convention home (default `docs/conventions`). The `registry_dir` option is read from user settings only, so a project `pluginConfigs` entry never applied. The cascade is the plugin data directory, then the option, then the team file, then the personal `harness-ops.local.yaml`, resolved by the new `scripts/registry-dir.mjs` through the shared config cascade.
- `/harness-ops:setup` reports which layer supplied the effective registry directory (`default`, `userConfig`, `team` or `local`) and the file that set it.

### Changed

- An invalid `registry_dir` (absolute, drive, UNC, `..`, an escaping symlink, or a character outside letters, digits, `.`, `_`, `-`, `/` and `\`, since the directory reaches a shell command) in any layer is now named with its layer, file and value and dropped, as the config cascade drops any invalid value: an invalid option or team value resolves to the plugin data directory, and an invalid personal value leaves the layer below it. `/harness-ops:known-issues` reports the dropped value and continues, where it used to stop the registry action on an invalid option.
