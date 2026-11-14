---
bump: minor
---

### Added

- Levels for `/prototype:explore-directions`: `sketch`, `standard` (the default, today's run) and
  `full` set the variant count, screens, states, evidence and offers. A run takes the level from
  `--level <name>`, then from the request ("the full package", "quick"), then from the settings,
  and prints one line naming the level and where it came from, such as `level: full (prompt)`.
- The plugin's first setting, `level`, as a `userConfig` option and in a repository's
  `docs/conventions/prototype.yaml` or `prototype.local.yaml`, beside a `levels` map that refines a
  shipped level or adds one. Keys: `reference/config.md`; schema:
  `schemas/prototype.schema.json`; shipped levels: `reference/levels.default.yaml`.
- `lib/prototype-settings.mjs`, which resolves them through the plugin's copy of the shared config
  cascade, and this plugin's copy of the shared convention-home resolver.
- Eval cases `ed-level-full-package` and `ed-level-config-default`.
