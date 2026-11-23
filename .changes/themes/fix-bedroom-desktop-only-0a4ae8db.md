---
bump: minor
---

### Changed

- The bedroom registers `/bedroom` and starts the room only once a desktop window shows the session: a terminal, VS Code, mobile or `claude -p` session lists no `/bedroom`, sets no theme and runs no minute clock, pieces or sound. A desktop window that attaches later starts the room then.
- `/bedroom` answers are shown to the person and no longer sent to the model. After the last desktop window detaches, `/bedroom` says no desktop window shows the session.
