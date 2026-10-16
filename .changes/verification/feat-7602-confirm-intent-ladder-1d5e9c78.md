---
bump: minor
---

### Changed

- `/verification:confirm` looks up intent on disk before asking: the PLAN.md Brief first, then the pull request body's acceptance criteria, then the linked issue, then the conversation, and the report names the source. With none and no one to ask, the verdict is `NOT VERIFIED: no intent source`.
