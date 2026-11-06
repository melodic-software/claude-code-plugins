---
bump: patch
---

`reach` uses the manifest's `/mnt/c` paths as given, without checking them with file tools or asking a subagent to, and says that each agent-starting command prompts under auto mode whether it runs, delegates or hands the command over.
