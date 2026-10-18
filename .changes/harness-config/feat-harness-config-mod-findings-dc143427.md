---
bump: minor
---

### Added

- `audit` Category F: `function-hooks-flag-dead` flags `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` in any user, project or local settings `env` as a dead mods switch, quoting the mods overview's line on the variable verbatim with the page URL and fetch date.
- `audit` Category D: `builtin-mods-survive-levers` quotes the mods overview's sentence on what `disableAllHooks`, `--bare` and `--safe-mode` do to Claude Code's built-in mods, verbatim with the page URL and fetch date, an `info` finding when `disableAllHooks` is set.
- Both rows read that sentence live: when the mods overview is not read, or no longer holds it, the row is `not-inspectable` saying the upstream statement could not be confirmed, with the pointer, and raises no finding. Runtime cost: the engine's existing fetcher call asks for one more page (the mods overview) through the docs cache, once per audit run.
- `audit-permission-state`: the merge prints a `CAVEAT: mods:` line saying deny rules are final against a user's mod only where the sec-default guard loads and never cover a mod's own `$.fs`/`$.process` calls, with the guard state read from the managed-scope records: not seated when a managed `prependPlugins` leaves the guard out, and flagged when managed settings set its `allowModsToOverrideDenyRules` option. Runs on demand only; no hook or per-turn cost.
