---
bump: major
---

### Changed

- **Breaking:** the plugin is renamed `context-usage`, after what it reports. Install it as `context-usage@melodic-software`; the slash commands are `/context-usage` and `/context-usage:setup`, and the status tool is `mcp__context-usage__status`. The options `context_usage_hooks_enabled`, `context_usage_band` and `context_usage_toast` (variables `CLAUDE_PLUGIN_OPTION_CONTEXT_USAGE_*`) replace the three options that carried the earlier name; `model_notices`, `zone_report_mode` and `zone_line_data` keep their names. Saved values move to the new keys through the operator's settings tooling, not reset.
- **Breaking:** the per-session snapshots, compaction markers, `zones.json` and the `cache-line.mjs` copy now live in `~/.claude/context-usage/`. `/context-usage:setup check` reports a directory left under the earlier name as drift, and `/context-usage:setup apply` moves `zones.json` unchanged, refreshes `cache-line.mjs`, prints any `statusLine` edit, and removes the old directory. Run it once on a machine whose dotfiles did not migrate it. Readers of the snapshot (`lib/context-zone.sh` and its copies) fall back to the old directory while a session that started before the update still writes there.
