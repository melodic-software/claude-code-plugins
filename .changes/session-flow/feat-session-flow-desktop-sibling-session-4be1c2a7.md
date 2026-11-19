---
bump: minor
---

### Added

- **`handoff` and the `workflow` router offer a new session on the desktop app.** When the session has a tool that starts another session (the Claude desktop app's Code tab), the rails resume prompt becomes the brief of a fresh session the user starts, instead of `/clear` and paste. The rules (the user starts it, the session runs in this checkout because the handoff file is gitignored, the `/loop` stays armed here, the `/clear` fallback) live in `reference/sibling-session-delivery.md`, read only in that case; without such a tool nothing changes.
- **`continue-in-background` starts a desktop session instead of `claude --bg` on the desktop app.** The started session gets the same `/goal` payload, runs in this checkout, and shows under this session in the sidebar, where a `claude --bg` agent does not appear; a refused start falls back to `claude --bg`. `--cloud` is unchanged.
- **`orient` and `reconcile` read the desktop app's session list.** With a tool that lists the user's other sessions, they take desktop sessions' state from it and keep transcript mtime for the sessions it does not show (CLI, VS Code, cloud); `reference/desktop-session-list.md`, read only in that case.
