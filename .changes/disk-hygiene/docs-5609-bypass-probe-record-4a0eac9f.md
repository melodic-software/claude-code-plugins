---
bump: patch
---

### Changed

- The safety model records the interactive bypassPermissions and auto-mode probes of the apply guard: its `ask` reaches a person or is denied in every probed mode, so no mode-independent gate is added (#5609).
