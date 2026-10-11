---
bump: patch
---

### Changed

- The audit and setup skills, the README and the Windows check catalog no longer restate how Claude Code names a plugin's data directory or quote the manifest reference on plugin variables. They point at the live sections with an as-of date and recheck trigger. The setup skill and the README keep the `-inline` name a `--plugin-dir` session gets as an observation the docs do not cover, citing the 0.7.0 CHANGELOG entry and a `setup check` probe as its recheck; the audit skill keeps its observation that the Bash tool can carry another plugin's `CLAUDE_PLUGIN_DATA` and now names the probe step that produced it. The catalog's `$CLAUDE_JOB_DIR/tmp` contrast now cites the agent-view section that documents its cleanup.
