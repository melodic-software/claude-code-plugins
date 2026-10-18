---
bump: minor
---

### Added

- `audit` Category F: `function-hooks-flag-dead` flags `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` in any user, project or local settings `env` as a dead mods switch, pointing at the mods overview for why.
- `audit` Category D: `builtin-mods-survive-levers` names `disableAllHooks`, `--bare` and `--safe-mode` beside the built-in mods section of the mods overview, an `info` finding when `disableAllHooks` is set.
- `audit-permission-state`: the merge prints a `CAVEAT: mods:` line saying deny rules are final against a user's mod only where the sec-default guard loads and never cover a mod's own `$.fs`/`$.process` calls, with the guard state read from the managed-scope records: not seated when a managed `prependPlugins` leaves the guard out, and flagged when managed settings set its `allowModsToOverrideDenyRules` option. Runs on demand only; no hook or per-turn cost.
