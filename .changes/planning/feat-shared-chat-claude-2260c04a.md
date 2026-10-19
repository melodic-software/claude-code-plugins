---
bump: minor
---

### Added

- Shared interview: "@Claude" in a chat message, or Ask Claude's new "About the whole session", asks Claude about the whole session. It waits for the host's Run like any guest request (the host's own runs at once), the Inbox lists it under General, and once shared Claude's answer replies in chat. The `result` op takes no `qid` for such a request; old session files load unchanged.
