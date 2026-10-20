---
bump: minor
---

### Added

- **A config layer declares its own workloads.** `workloads.<w>: true` in any layer declares workload `<w>`, so `roles.<role>.workloads.<w>.model` and `.effort` apply and `/multi-agent:route <role> <w>` resolves it; `false` withdraws one. The bundled layer declares `code`, `research` and `mechanical` the same way, in `reference/defaults.yaml`. A workload value for a name no layer declares is still reported and ignored, and an undeclared `--workload` exits 2 listing the declared ones.

### Changed

- `/multi-agent:route` takes the workload as its second bare argument, so a declared name passes through; `code`, `research` and `mechanical` work as before.
