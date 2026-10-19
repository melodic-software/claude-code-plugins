---
bump: patch
---

### Fixed

- `best` is no longer a role model, a frontier alias or an accepted `--session-model`: the resolver rejects it as an unknown alias, and the bundled `frontier` default is `fable`. The config reference now points at sub-agents: choose a model for the subagent aliases and model fallback. (#7990)
