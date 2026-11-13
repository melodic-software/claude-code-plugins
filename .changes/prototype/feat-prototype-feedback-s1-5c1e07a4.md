---
bump: minor
---

### Added

- `/prototype:explore-directions` can serve its mockup through a notes host when the person wants
  to pin notes in the page (`reference/feedback.md`). The host page frames the mockup in a sandbox,
  the person picks an element and writes a note, and the session reads each note as data through
  the session bridge's watcher, restates it, and replies on the page. The `file://` mockup and its
  copy-out stay the default.
- `notes-bridge/`: this plugin's copies of the shared ui-feedback parts (host page, pin helper,
  note schema and validator, notes bridge app) and the session-bridge files they run on.
- `python3` and `curl` prerequisite rows (optional; without them, the mockup stays copy-out only).
- Eval case `ed-notes-tracer`.

### Changed

- The `shipments-mockup.html` eval fixture carries proposed test ids, as every mockup does.
