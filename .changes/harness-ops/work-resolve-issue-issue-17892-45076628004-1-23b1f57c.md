---
bump: minor
---

### Added

- `/harness-ops:audit-mod-posture` now reports whether a mod Claude writes in a session can load without asking. A new `# claude-written mods:` footer reads `load-unasked` when `permissions.defaultMode` is `auto` or `bypassPermissions` and managed `disableSideloadFlags` is not `true`. A lower mode set in project or local settings, such as `plan` or `dontAsk`, still overrides the user's mode. Criterion M6 scores that footer.
- Criterion M7 flags any enabled mod that calls `$.tool.call` or `$.mcp.call`, since those calls can skip permission prompts and `ask` rules.
- The inventory has a new `nouns` column. It lists the `$` namespaces each mod's `engine.create` hook adds, withholds or replaces, read from `claude plugin validate`. Criterion M8 scores the column.

### Fixed

- A mod whose validate output reads `calls: nothing on $` now shows `-` in its `calls` column. Before, the column showed `redacted`.
