---
bump: patch
---

### Fixed
- The notes host page's Mark a region (R) now reaches past the frame: a drag held near the frame's top or bottom edge scrolls the mockup, so a region can cover a list taller than the frame. A drawn region moves when dragged and resizes from its edges and corners, or with the arrow keys and Enter, before its note is sent or after, from the editor's or the row's Move or resize. A sent note's new box goes to the session as a change naming that note (`POST /api/note/change`, `note.schema.json` x-version 7).
