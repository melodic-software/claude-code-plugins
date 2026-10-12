---
bump: patch
---

### Fixed

- `/harness-ops:audit-performance`'s concurrency-ceilings step now tells the reader never to present any value, or removing the variable, as disabling either subagent cap, and not to relay the engine's `ceilings.trap` string for the caps; it points at the sub-agents and env-vars sections for accepted values and exemptions. The engine's `trap` string itself is unchanged, because `scripts/test_audit_performance.py:910` pins its text.
- `/harness-ops:audit-install-state` routes `~/.claude.json` growth to `claude purge` in Phase 5, matching its own reference, and its engine now classifies `uploads/`, `dev-mods/` and `usage-data/` as swept and `jobs/` as kept instead of unclassified; the new and changed table notes are short labels with a docs pointer.
- The `plugins` scope reference quotes the current `/plugin` install-summary line for a needed reload, and no longer says the summary's version is read from a pointer that names none.
- `reference/surfaces.md` stops claiming that the absence of `image-cache/` or `feedback-bundles/` proves the sweep ran, and stops stating that `history.jsonl` is never trimmed.
- The `plugins` gotchas no longer quote a sentence about the previous-version orphan sweep that the plugin loading page does not contain; they point at its cleanup section instead. `behavior-probes` anchors its authoritative-denial gotcha, and `observability` drops a restated raw-API-body truncation limit beside its pointer.
- The `plugins` scope reference re-derives its "nothing reaps project-scope records" claim now that the swept-path list names paths under `~/.claude/plugins/`.

### Changed

- Restated upstream specifics (retention defaults, swept and kept path tables, the managed-source refusal, hook and statusline shell rules, listing-budget defaults, `enabledPlugins` precedence, plugin version floors, telemetry attribute defaults, release-note details) are replaced with anchored pointer records dated 2026-10-11 across `audit-install-state`, `audit-performance`, `audit-native-overlap`, `audit-skill-visibility`, `check`, `prerequisites`, `machine-profile`, `plugins`, `lanes` and `observability`.
