---
bump: minor
---

### Added

- `/prototype:explore-directions` re-locates each note in a fresh page before restating it
  (`reference/feedback.md`, "Re-locating a note"): `notes-bridge/relocate-note.mjs` writes a
  `playwright-cli run-code` script that carries the note as one JSON literal, restores the note's
  variant, screen state and content set, runs the anchor ladder in the sandboxed frame, and saves a
  shot of the element from inside the frame. A note whose element is gone gets a position-only
  shot of its stored box, and the session asks instead of editing.
- Notes carry the picked element's box (`rect`, percent of the page), the position-only last rung.
- The variant switcher listens for a `vs:show` event that restores a variant, screen state and
  content set. Pages that never send it behave as before.
- Eval case `ed-notes-relocate-not-found`.
