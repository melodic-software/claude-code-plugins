---
bump: patch
---

### Fixed

- **The observability setup produces telemetry again on current Claude Code.** The setup put the keys that turn Claude Code's telemetry on, pick the exporters and endpoint, and capture content in the committed `.claude/settings.json` and in `.claude/settings.local.json`, which Claude Code no longer honors for those keys, so nothing was exported. The setup now puts them in each developer's user settings or shell, keeps only structure-only keys in the committed project settings, uses the ignored-variables report at startup and in `/status` as the health check, and links the settings reference for the current list.
- **The repository columns in the OTEL store fill.** The setup now sets `OTEL_METRICS_INCLUDE_REPOSITORY=true`, so the `vcs_repository_*`, `vcs_owner_name` and `vcs_provider_name` columns stop coming back empty, and it notes that the `vcs_ref_head_*` commit columns also need `OTEL_LOG_TOOL_DETAILS=1` in user scope.
- **Purge advice names the current command.** `/harness-ops:audit-install-state`, `/harness-ops:audit-performance`, `/harness-ops:audit-skill-visibility` and the install-state report now route project-state removal to `claude purge` instead of the deprecated `claude project purge`.
