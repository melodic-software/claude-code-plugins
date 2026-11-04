---
bump: minor
---

### Changed

- `/source-control:babysit-loop` no longer counts an issue in a cordoned milestone toward either `--drain` exit. Its snapshot reads the names from `cordoned-milestones` in the target's `admission-rules.json`; a repository without that file cordons nothing.
