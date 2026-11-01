---
bump: patch
---

### Added

- Frozen description-trigger probes for `check-prerequisites` under `probes/` ([#6591](https://github.com/melodic-software/claude-code-plugins/issues/6591)).

### Changed

- The `check` description drops its quoted trigger list and action reference for one trigger per capability, 1013 to 382 characters, keeping the `/evals:validate` pointer for new eval cases. In held-out trigger probes on Opus, positive queries fired in 24 of 24 runs (20 of 24 before), and negative queries stayed quiet in 21 of 24 runs, the same as before.
- The `check-prerequisites` description is shorter, 328 to 258 characters. In held-out trigger probes on Opus, positive queries fired in 24 of 24 runs, as before, and negative queries stayed quiet in 18 of 24 runs (19 of 24 before), within the 5-point margin and with no new false-firing query.
