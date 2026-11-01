---
bump: patch
---

### Added

- Frozen description-trigger probes for `methodology` and `simulation` under `probes/` ([#6580](https://github.com/melodic-software/claude-code-plugins/issues/6580)).

### Changed

- The `methodology` description is shorter and names its siblings: `/event-storming:simulation` for an AI-simulated workshop, `/planning:design` for types and module boundaries, and `/architecture:map-events` for message topology read from code. In held-out trigger probes on Opus, positive queries fired in 19 of 24 runs (16 of 24 before), with no false fires on 24 negative runs. The `simulation` description is unchanged.
