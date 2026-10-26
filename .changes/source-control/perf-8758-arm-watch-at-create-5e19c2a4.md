---
bump: minor
---

### Changed

- `/source-control:pull-request create` arms event delivery for the PR it opened (the push channel, else the Monitor watch; polling in a cloud session) when the session will keep acting on it, through Steps 1-3 of the Monitor entry checklist, instead of ending Phase 2 and leaving monitoring to a separate `monitor` invocation. `create --pushed` still hands monitoring to its caller, which arms delivery through the same checklist.
