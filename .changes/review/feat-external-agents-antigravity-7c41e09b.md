---
bump: minor
---

### Added

- `/review:council` takes `antigravity` (Gemini through agy) members, run as `external-agents review antigravity --council`, so `antigravity.council.enabled` in `external-agents.yaml` can turn them off. Like Codex members they set a model and a brief but no effort, review committed history only, and are opt-in: add one to `council_members`, for example `{"gemini":{"provider":"antigravity"}}`.
