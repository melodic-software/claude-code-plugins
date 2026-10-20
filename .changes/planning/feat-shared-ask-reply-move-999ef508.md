---
bump: minor
---

### Changed

- The shared page's top Ask Claude button now asks about the whole session; a question's own Ask form still asks about that question.

### Added

- A Reply button on every Claude answer opens a new ask that quotes the answer.
- Move to on a request puts it, with its answer, on another question or the whole session. Only its asker or the owner can move it (`/api/request/act` action `move`).
