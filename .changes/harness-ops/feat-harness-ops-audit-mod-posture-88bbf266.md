---
bump: minor
---

### Added

- **`/harness-ops:audit-mod-posture`**: a read-only inventory of the mods this Claude Code can run. Installed mods are found by `modules` in `hooks/hooks.json` (or an inline hooks object) and read with `claude plugin validate`, which does not load them or change their directory; built-in mods come from an `/harness-ops:inventory` report, with whether each can be turned off read from the live mods overview. Each row's tier is its install scope (managed, local, project or user) or builtin, and a built-in reads on only when its setting is on and it is not gated (a gated one reads off when a listed gate flag is false, else unknown). It states whether the built-in guard is seated (managed settings, or a Team or Enterprise plan) and scores M1-M5. It prints names only, never settings, env or account values. Runtime impact: on demand only, no hook. The installed tier takes about 3.5 s (five mods on the measured host: validate per mod plus one cached docs fetch); the inventory report the built-in tier reads took about 41 s and is produced only when built-ins are wanted. Without it, a footer says built-in mods were not read.
