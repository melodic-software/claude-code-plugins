---
bump: minor
---

### Added

- **`handoff` and the `workflow` router offer a new session on the desktop app.** When the session has a tool that starts another session (the Claude desktop app's Code tab), the rails resume prompt becomes the brief of a fresh session the user starts, instead of `/clear` and paste. The rules (the user starts it, the session runs in this checkout because the handoff file is gitignored, the `/loop` stays armed here, the `/clear` fallback) live in `reference/sibling-session-delivery.md`, read only in that case; without such a tool nothing changes.
