---
bump: minor
---

### Added

- `/implementation:implement` reads the `verification` level at each phase boundary: `light` and `off` skip the fresh-context verifier and write `verification: skipped (<level>)` in the plan mark unless `verify_mechanical_phases` resolves `true`; `strict` turns `verify_mechanical_phases` on.
- `/implementation:implement` and `/implementation:implement-dispatch` read the level from `docs/conventions/implementation.yaml`, beside the plugin's other keys, through `read-verification.sh --file`, whatever convention home the repository binds.
