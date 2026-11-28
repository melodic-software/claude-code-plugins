---
bump: patch
---

### Changed

- Trimmed `harness-config` skill frontmatter descriptions (`audit` 474 -> 345 chars, `audit-automation-gaps` 457 -> 345 chars, `audit-instructions` 494 -> 344 chars, `audit-pass` 485 -> 346 chars, `audit-permission-grants` 498 -> 347 chars, `audit-permission-state` 497 -> 342 chars, `audit-prompting-postures` 495 -> 347 chars, `draft-auto-mode-rules` 489 -> 346 chars, `setup` 661 -> 141 chars, `unhobble` 497 -> 349 chars; total 5047 -> 3252 chars, -1795 chars) while preserving native-overlap `resolves in this session` clauses, report-only/confirmation postures, and all action modes.
- The `audit-prompting-postures` description now names its neighbor as `/harness-config:audit-instructions`, with the plugin prefix.
