---
bump: minor
---

### Changed

- **`implement-dispatch` runs independent plan phases in one wave by default.** Phases the approved plan's Execution shape puts in the same parallel wave now dispatch together without the user asking, instead of strictly one phase at a time. Fence composition, the one-writer rule, the wave cap, the wide-wave pilot and the frontier-tier rule count every row in the wave; each phase keeps its own build/test gate, `phase-verifier` and phase-boundary commit. A plan with a sequential shape still runs in order. A phase routed to an agent team runs as one only when agent teams are enabled for the session; otherwise its rows go out as sub-agent workers, dispatched without a `name` so they cannot launch as teammates. `implement_dispatch_wave_cap` now counts rows across every phase in a wave.
