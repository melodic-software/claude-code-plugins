---
bump: minor
---

### Added

- The bundled setup writer, `lib/setup-apply.mjs`, takes `--state`, which prints the repository's state (`init`, `migrate` or `configure`) and the path that shows it, and writes nothing. It can also migrate values from a retired settings file that a `retirements.yaml` record names, printing any value it cannot carry and leaving that file in place. This plugin's setup names no such record yet, so its own writes are unchanged.
