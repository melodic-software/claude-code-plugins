---
bump: minor
---

### Added

- `audit-permission-state`: the permission-plane lint's new `C6-assignStar` warning flags a Bash allow rule with a `*` in a leading variable assignment, such as `Bash(PORT=* npm run dev)`. Claude Code v2.1.323 and later warn about this shape at startup; the lint finds it across every scope before a session starts.
