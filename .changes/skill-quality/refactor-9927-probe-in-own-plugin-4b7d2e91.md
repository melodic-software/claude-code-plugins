---
bump: patch
---

### Changed

- The `mcp-tools:audit` seed probe and its baseline rows move to the `mcp-tools` plugin's `probes/`, so no file under this plugin's `probes/` holds a path into another plugin ([#9927](https://github.com/melodic-software/claude-code-plugins/issues/9927)). `probes/baselines/listing-overlap.json` keeps the `skill-quality:check` rows unchanged. `reference/invocation-probes.md` and the `check` skill name where each seed probe set now lives and say to compare a plugin's score against that plugin's baseline; `score`'s no-resolvable-probe error no longer names `plugins/mcp-tools/...` as a seed path.
