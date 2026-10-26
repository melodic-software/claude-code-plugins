---
bump: minor
---

### Added

- behavior-probes gains a `prints` outcome that judges the first line a slash command prints, a per-case `cli_args` list limited to allowed flags (today `--autocompact`), and `PROBE_MODEL` in a scaffold's environment. A `prints` case can name a control, and a control's own control now counts too.
- A new `autocompact` area: four cases that run `/autocompact` with no argument and check which window wins between a project file's top-level and per-model `autoCompactWindow`, the `--autocompact` flag, and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. Each case adds one element to the case it names as its control. They pass in the dry run and have not run live yet.
