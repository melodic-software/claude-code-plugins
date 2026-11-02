---
bump: patch
---

### Fixed

- `list-items` and `list-frontier` on the GitHub adapter no longer exit 3 in a Claude Code cloud session, whose GitHub proxy refuses GraphQL. They read the REST issues endpoint instead, and call the `dependencies/blocked_by` endpoint only for an issue whose dependency summary counts a blocker. A `/work-items:work-loop` cycle in a cloud session now reaches admission, with the same blocker counts a local session gets.
