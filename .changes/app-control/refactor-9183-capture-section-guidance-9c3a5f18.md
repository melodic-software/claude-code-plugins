---
bump: minor
---

### Added

- `reference/control-skill.md` gains "Writing the Capture section": a symptom-to-tool table per runtime (spin, leak, jank, hang) with each tool's manual, as guidance for whoever writes a control skill's `## Capture`. `/app-control:drive` still picks no tool itself.
- `/app-control:drive` gains a `threads` capture kind, a stack sample of every thread, for a process that stops responding; jank stays `trace`.
