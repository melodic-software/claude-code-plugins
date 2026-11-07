---
bump: minor
---

### Added

- The GitHub `get-statuses` read counts a Work status value only from a trusted setter when the binding sets `config.github.status_trust` (trust list, model and lanes App): a listed human or the lanes App for any state, a `models.issue-status` bot-setter for every state but `agent-ready`. The newest counted field event decides. A missing or invalid trust configuration exits `3`, so `list-frontier --autonomous` fails closed on it.
