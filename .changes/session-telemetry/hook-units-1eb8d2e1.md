---
bump: minor
---

### Added

- The `session-telemetry` plugin, off by default: the session-wide recorder harness-ops carried. Eight `*-audit` rows emit the hook-telemetry envelope for API errors, config changes, instruction loads, permission denials, compactions, tool failures and skill use (the Skill tool and slash-command expansion); the reference sink writes the hook log root; the hooks module keeps the default-off per-session hook event log and its SessionEnd retention. Its options are the ones those hooks had in harness-ops, under the same names: set them again for `session-telemetry@<marketplace>`.
- `HOOK_TELEMETRY_SINK=@session-telemetry` resolves to the launcher this plugin keeps in its data directory; `@harness-ops` resolves to the same launcher, so existing wiring keeps working.
- `skill-usage.jsonl` is size-capped: past the new `skill_usage_max_bytes` option (default 10485760) it moves to `skill-usage.jsonl.1`, replacing any older `.1`, the rule `hook-events.jsonl` follows. A store at the repo root (`skill_usage_dir=.`) keeps the store, its `.1` and its `.lock` out of `git status`.
- At each session start the plugin writes `options.json` in its data directory, the options its hooks run with, so a skill in another plugin can find the records (`docs/contracts/session-telemetry-data`).
