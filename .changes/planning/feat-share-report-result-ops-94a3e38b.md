---
bump: minor
---

### Added

- Shared interviews: Claude's `share.sh apply` takes `resolve-report` (mark a problem report seen or resolved), `share-result` and `take-down-result` ops, so the session does what the owner asks in the terminal instead of asking the owner to click it. Each runs the owner page's own action, with its checks and the notice the reporter or asker gets.
