---
bump: minor
---

### Added

- `plan`: `plan_stress_test` sets, per mode of the draft (`plan`, `proposal`, `incumbent`), which stress-tests `/planning:plan` runs: `auto` (the default, current behaviour), `reviewer`, `devils-advocate` or `both`. It resolves through the convention home; `reference/config.md` defines the modes and values (#12478).
- `evals`: the `plan-stress-test` suite, 12 seeded drafts across the three modes with deterministic graders, and `fixtures/stress-arm/prepare-arm.sh`, which sets up a plugin copy for one arm or for the suite's negative control (#12478).
