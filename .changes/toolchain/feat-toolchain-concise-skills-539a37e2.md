---
bump: minor
---

### Changed

- `check`'s body and the `check` and `lint` descriptions are shorter, and `check`'s CI-parity gate rules move to `context/gates.md`. `setup`'s description is a one-line summary, since it is user-invoked. `check` names its next step in a `## Next` section. `lint` keeps its original body, because the shorter one was not shown to hold on Sonnet.

### Added

- Six outcome eval cases for `check` and `lint` under `evals/`, and frozen trigger-probe sets under `probes/`.
