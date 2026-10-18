---
bump: minor
---

### Added

- **`/harness-ops:audit-mod-posture`**: a read-only inventory of the mods this Claude Code can run. Installed mods are found by `modules` in `hooks/hooks.json` (or an inline hooks object) and read with `claude plugin validate`, which does not load them or change their directory; built-in mods come from an `/harness-ops:inventory` report, with whether each can be turned off read from the live mods overview. It states whether the built-in guard is seated (managed settings, or a Team or Enterprise plan) and scores M1-M5. It prints names only, never settings, env or account values. Runtime impact: on demand only, no hook; about 0.6 s per installed mod for validate plus one cached docs fetch.
