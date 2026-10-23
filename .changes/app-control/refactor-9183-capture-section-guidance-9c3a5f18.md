---
bump: minor
---

### Added

- `reference/control-skill.md` gains "Writing the Capture section": a symptom-to-tool table per runtime (spin, leak, jank, hang) with each tool's manual, as guidance for whoever writes a control skill's `## Capture`. `/app-control:drive` still picks no tool itself.
- `/app-control:drive` gains a `threads` capture kind, a stack sample of every thread, for a process that stops responding; jank stays `trace`.
- A `threads` artifact routes to `/debugging:analyze-profile` in `## Next`.

### Changed

- The shown-script elevation step now covers a capture on a process the run launched, not only an attach; with no one present that capture is `blocked: capture needs elevation`.
