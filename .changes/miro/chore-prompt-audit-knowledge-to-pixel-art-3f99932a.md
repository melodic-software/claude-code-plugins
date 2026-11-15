---
bump: patch
---

### Changed

- `miro_bulk_create_sticky_notes` says a mid-batch failure returns an error without the IDs of
  notes already placed, so check the board before retrying. `miro_attach_tag` states what it
  returns and that it errors on an item type that takes no tags.
- The setup skill names its one API gate: a request runs only when `verify-api` was passed, and
  only the read-only call.
