---
bump: patch
---

### Fixed

- The README no longer says a `PreToolUse` hook that exits 0 with nothing to say approves the call, and it states that no registration in this plugin sets a hook failure option; the outcome of a failed launch is read from the hooks page.
- The kill-switch reader's docstring no longer calls every platform's managed-settings path admin-only; whether a process running as the user can write it is read from the managed-settings page.

### Changed

- Comments and docs that restated Claude Code behavior (hook exit codes and failed launches, `pluginConfigs` scopes, managed-settings paths, hook lifetime in skills and subagents, permission-mode handling of hook `ask`, auto-mode allow rules) now point at the exact live docs section with an as-of date and a recheck trigger. Guard logic is unchanged.
