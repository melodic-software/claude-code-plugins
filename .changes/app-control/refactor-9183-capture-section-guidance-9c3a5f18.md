---
bump: patch
---

### Added

- `reference/control-skill.md` gains "Writing the Capture section": a symptom-to-tool table per runtime (spin, leak, jank, hang) with each tool's manual, as guidance for whoever writes a control skill's `## Capture`. `/app-control:drive` still picks no tool itself.

### Changed

- The shown-script elevation step now covers a capture on a process the run launched, not only an attach, including a named command that carries an elevation prefix; with no one present that capture is `blocked: capture needs elevation`.
- "Writing the Capture section" bars elevation prefixes (`sudo`, `doas`, `runas`) in a `## Capture` command and elevates only the recorder against a pid. The hang row names no capture kind yet (#9490).
