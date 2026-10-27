---
bump: patch
---

### Added

- `probes/audit.json`, the `/mcp-tools:audit` invocation probe set (against `mcp-tools:audit-posture`), and its `probes/baselines/listing-overlap.json` floor, moved unchanged from the `skill-quality` plugin so each probe set sits in the plugin it measures ([#9927](https://github.com/melodic-software/claude-code-plugins/issues/9927)). CI validates it with the other `plugins/*/probes` directories.
