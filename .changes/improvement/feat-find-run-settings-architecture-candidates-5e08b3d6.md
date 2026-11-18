---
bump: minor
---

### Added

- New `.claude/improvement.md` keys for unattended `/improvement:find`: `find_run_item_cap`, `find_run_item_cap_floor`, `find_run_item_cap_ceiling`, `find_size_band`, `find_scope` and `find_suppress_dismissed`. Each resolves from the invocation prompt, then config, then the bundled default, and the defaults match today's behavior.
- Unattended `/improvement:find` runs `/architecture:improve deepening --unattended` inline when that skill is available, and files its verified `Strong` candidates under the `source: architecture-improve` label, with their own open cap.

### Changed

- `find_open_item_cap` applies to each source label separately, and personal layers can only lower it: a higher user-global or `.local` value is ignored and reported.
