---
bump: patch
---

### Fixed

- Shared sessions: a tab hidden, or set Away by hand, while a plain heartbeat was waiting out its one-second gap now sends its Away beat at once. Before, that beat waited for the gap's timer, which a throttled or frozen background tab may run only a minute later, so the person showed Active until then.
