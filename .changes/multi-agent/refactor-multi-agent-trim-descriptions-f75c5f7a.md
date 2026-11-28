---
bump: patch
---

### Changed

- Trimmed frontmatter descriptions across all four `multi-agent` skills (`assess` 417 -> 287 chars, `audit-defaults` 692 -> 346 chars, `route` 822 -> 350 chars, `setup` 167 -> 124 chars; total 2098 -> 1107 chars, -991 chars) while preserving all modes, read-only/propose-only safety posture, and sibling exclusions. The `assess` description names its verdict values as `workflow`, `subagent` and `single`, the values its output emits.
