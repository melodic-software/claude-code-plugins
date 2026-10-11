---
bump: patch
---

### Fixed

- `/harness-ops:audit-performance` no longer says either subagent cap is disabled by removing its variable; neither cap can be turned off. The skill item and the engine's `ceilings.trap` string now limit the truthiness wording to the observer flag and point at the sub-agents sections for accepted values.
- `/harness-ops:audit-install-state` routes `~/.claude.json` growth to `claude purge` in Phase 5, matching its own reference, and its engine now classifies `uploads/`, `dev-mods/` and `usage-data/` as swept and `jobs/` as kept instead of unclassified, with a corrected `backups/` note.
- `reference/surfaces.md` stops claiming that the absence of `image-cache/` or `feedback-bundles/` proves the sweep ran, and stops stating that `history.jsonl` is never trimmed.
- The `plugins` scope reference re-derives its "nothing reaps project-scope records" claim now that the swept-path list names paths under `~/.claude/plugins/`.

### Changed

- Restated upstream specifics (retention defaults, swept and kept path tables, the managed-source refusal, hook and statusline shell rules, listing-budget defaults, `enabledPlugins` precedence, plugin version floors, telemetry attribute defaults, release-note details) are replaced with anchored pointer records dated 2026-10-11 across `audit-install-state`, `audit-performance`, `audit-native-overlap`, `audit-skill-visibility`, `check`, `prerequisites`, `machine-profile`, `plugins`, `lanes` and `observability`.
