---
bump: patch
---

### Fixed

- `intake-reenter` now sends back to intake a `status: confirmed` issue that a person confirmed before any admission when a listed human posts a `**Decision recorded.**` comment on it. Before, only an issue admission had parked there re-entered, so a decision on a hand-confirmed issue changed nothing. An issue with `agent-ready` or another `status:` label still stays where it is.
