---
bump: patch
---

### Fixed

- `/fleet:reach` uses the manifest's `/mnt/c` paths as given, never checking them with file tools or asking a subagent to.
- `/fleet:reach` says that each agent-starting command prompts under auto mode, whether it runs, delegates or hands the command over.
