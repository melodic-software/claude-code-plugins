---
bump: patch
---

### Changed

- `audit-automation-gaps` no longer names one ecosystem's build files or file extensions when it
  inventories enforcement and codebase shape. It reads the repository's own build configuration
  and counts files per extension over `git ls-files`.
- `audit-automation-gaps` drops the recorded `git log --grep` counts from this marketplace. The
  rule stays the same: a keyword count is a ceiling, never a frequency.
- `audit`, `audit-permission-grants`, `audit-permission-state` and `setup` reference pages show
  permission-rule syntax with `git` commands and placeholders, not package-manager or interpreter
  commands from one ecosystem.
