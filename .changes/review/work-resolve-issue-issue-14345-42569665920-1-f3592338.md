---
bump: patch
---

### Changed

- Simplified the generated session_bridge.py copy: the two transports share one listener view, the token checks share one compare, and the session-file readers reuse read_json. Behavior is unchanged.
