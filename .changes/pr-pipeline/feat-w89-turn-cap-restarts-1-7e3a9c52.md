---
bump: minor
---

### Changed

- This repository sets `limits.turn-cap-restarts` to 1: one run that reaches its turn cap resumes from its pushed branch per `agent-ready` a listed human adds, then goes to a person. The built-in default stays 0.
