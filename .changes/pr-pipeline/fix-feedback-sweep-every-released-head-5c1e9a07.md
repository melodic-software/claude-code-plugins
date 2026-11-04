---
bump: patch
---

### Fixed

- The half-hourly address-feedback sweep now sends every eligible lanes App head on one tick, up to five (`SWEEP_TICK_CAP`), instead of only the first. Before, each released head after the first waited one more tick, about 30 minutes, per PR. The sweep runs its passes in the same order (fix request, released, stale stop, unsent, idle owner) and decides each PR at most once. It stops deciding after five minutes (`SWEEP_DECIDE_BUDGET_MS`), then sends the decided rounds back to back, so each dispatched-run record uploads seconds after its POST, well within the trusted-trigger gate's wait. `pr-feedback-dispatch.yml` records each send through its own numbered steps. Lost-run recovery still runs only on a tick that sent nothing.
