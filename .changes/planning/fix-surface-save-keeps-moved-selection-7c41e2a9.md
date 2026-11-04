---
bump: patch
---

### Fixed

- **A save that finishes after you moved to another question leaves you there.** The interview page
  moved to the next question once a save's refresh returned, counting from whatever question was
  selected by then, so a click made while the save was in flight was undone and the next keystroke
  could answer a question you had not opened. It now stays on the question you moved to and keeps
  its armed choice; the toast still reports the save and offers Undo.
