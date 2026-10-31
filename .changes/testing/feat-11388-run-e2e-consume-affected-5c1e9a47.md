---
bump: minor
---

### Added

- **run-e2e:** `app=`, `base=` and `trusted-root=` arguments, passed to every `/app-control:drive` call. An `unattended` run writes `e2e-summary.json`: the route, the touched features, a `capture` status (`ran`, `not-applicable`, `blocked` or `skipped`) with its reason, one line per entry point, and a `publishable` list the file joins only after a scan finds no hit ([#11388](https://github.com/melodic-software/claude-code-plugins/issues/11388)).

### Changed

- **run-e2e:** touched features come from `/app-control:drive affected`; the skill no longer matches changed files against a control skill's `sources` globs itself. Without app-control the report says `touched features not matched (app-control not installed)` ([#11388](https://github.com/melodic-software/claude-code-plugins/issues/11388)).
