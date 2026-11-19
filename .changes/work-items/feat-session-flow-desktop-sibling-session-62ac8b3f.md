---
bump: minor
---

### Added

- **`ship` offers one session per ready item on the desktop app.** In the `per-item PRs` shape, when two or more independent items are ready and the session has a tool that starts another session, `ship` offers a session per item, each in its own worktree with a brief that claims the item first; `context/parallel-sessions.md` holds the rules and is read only in that case. The integration-branch shape never gets it.
