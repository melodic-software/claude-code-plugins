---
bump: patch
---

### Changed

- Trimmed `/fleet:reach` frontmatter description (495 -> 343 chars, -152 / -30.7%). It keeps the cross-host/cross-platform verbs (`run`, `prompt`, `query`, `message`, `start`) and WSL/Windows targeting. The quoted triggers are cut to three (`'run this on HOST'`, `'from WSL to Windows'`, `'remote agent'`) and the others are dropped. The exclusions are `ListAgents`/`SendMessage` and `/session-flow:continue-in-background`, and repository fleets now route to `/repo-fleet-hygiene:audit` only.
