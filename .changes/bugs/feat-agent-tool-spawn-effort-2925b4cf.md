---
bump: patch
---

### Changed

- scan: gates now receive the role map's verifier effort as the Agent tool's per-spawn `effort`, and never run at a lower effort than the hunters; hunters still run at the session level. The report and README name each stage's effort as well as its model. With no role map both stages run at the session level.
