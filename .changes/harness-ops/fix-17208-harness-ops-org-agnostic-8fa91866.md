---
bump: minor
---

### Added

- `probe_state_issue` option and `harness-ops.yaml` key: the issue, as `<owner>/<repo>#<number>`, the `cloud-routine/state-read-back-next-run` behavior probe works against. `scripts/probe-state-issue.mjs` resolves it and `probe.py run --state-issue` takes it. With none set, a live run skips the case.
- `otel_store_reset_doc`, `otel_collector_config_ref` and `otel_dashboards_compose_ref` options: where your machine provisioning documents the OTEL store reset, the Collector configuration and the dashboard compose file. `/harness-ops:observability` shows them and links nothing when they are unset.

### Changed

- When `CLAUDE_PLUGIN_DATA` is not usable, the inventory parser, the control-claude-code driver and the known-issues registry now name their data directory after the marketplace this plugin is installed from, as Claude Code does. Before, they used a fixed directory name. Outside the plugin cache they use `harness-ops-inline`, the name Claude Code gives a `--plugin-dir` session's data directory.
- The behavior-probe cases and skill text no longer name a particular organization's repository. The auto-mode `gh secret` cases target `probe-owner.invalid/probe-repo`, a name no GitHub login can have.
