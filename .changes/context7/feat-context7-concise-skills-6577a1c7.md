---
bump: minor
---

### Changed

- `lookup`, `check` and `setup` have shorter bodies, and `lookup` and `setup` shorter descriptions. Eval cases and trigger probes measured each change against the old text before it shipped. The vendored upstream baselines and the sync metadata are unchanged.

### Added

- Seven outcome eval cases for `lookup`, `check` and `setup` under `evals/`, and a frozen trigger-probe set for `lookup` under `probes/`.
