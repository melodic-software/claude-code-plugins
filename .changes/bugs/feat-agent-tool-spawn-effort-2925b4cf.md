---
bump: patch
---

### Changed

- scan: hunters and gates now receive the role map's effort as the Agent tool's per-spawn `effort` (hunters on the `retrieval` role, gates on `verifier`), a gate never runs at a lower effort than the hunters, and the report names each stage's effort. With no role map both stages still run at the session level.
