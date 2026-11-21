---
bump: minor
---

### Added

- A sent note on the notes host page now has Edit and Withdraw. An edit goes to the session as that note's new text under the same seq (`POST /api/note/edit`); a withdraw tells the session and lists the note as withdrawn, not pending, with no marker, and leaves it out of `status`, the watcher's unhandled notes and Copy all notes (`POST /api/note/withdraw`, `note.schema.json` x-version 8).
