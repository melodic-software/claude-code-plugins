---
bump: patch
---

### Fixed

- The pr-unblock and feedback dispatchers wait out a rate limit on the repository's job token instead of failing at once: retry-after when GitHub sends it, else until one second past the reset when no requests remain, else one minute, then the call is sent once more. Waits are capped at six minutes per run, summed; a reset further away fails at once and names the reset time.
- The lost-run reconciler re-runs, once, the failed jobs of an intake-label-needs-triage run whose first attempt failed within its lookback, so an issue the floor label missed (a rate limit, most often) gets it on the next tick.
