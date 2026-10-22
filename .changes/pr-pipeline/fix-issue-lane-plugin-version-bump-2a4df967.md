---
bump: minor
---

### Added

- Patch rules: an optional `plugin-version-bump` row key, set on the `issue` row, lets `instruction-path` pass a `plugins/<plugin>/.claude-plugin/plugin.json` change whose only difference is its top-level `version` string.

### Fixed

- The issue lane can bump a plugin's version again; every other `plugin.json` change stays refused.
- work-resolve-issue's report-outcome names apply-issue-patch's escalation reason when it refused a done run's patch, instead of saying the run committed nothing.
