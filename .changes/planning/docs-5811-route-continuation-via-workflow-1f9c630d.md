---
bump: patch
---

### Changed

- `/planning:interview` routes a continuation that outgrows the session (a pause, branches outgrowing it, or a worsened context zone) through `/session-flow:workflow`, handing it the ledger, Brief and first open branch, instead of choosing a handoff and clear itself.
