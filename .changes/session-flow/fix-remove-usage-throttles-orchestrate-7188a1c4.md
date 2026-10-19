---
bump: patch
---

### Fixed

- `/session-flow:orchestrate` no longer caps workers on usage or rate-limit headroom, and picks the cheaper model tier by whether the work is mechanical or judgment, not by fan-out width. Backoff on this session's own rate-limit errors and sibling 429s stays.
