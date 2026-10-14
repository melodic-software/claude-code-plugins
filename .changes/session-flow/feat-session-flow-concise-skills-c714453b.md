---
bump: minor
---

### Changed

- Shorter descriptions and tighter bodies for `clean-stop`, `find-handoff`, `handoff`, `keep-going`, `orchestrate`, `orient`, `reanchor`, `recall`, `reconcile`, `retro`, `running-retro`, `show-options` and `workflow`. Every gate, stop, command and report line stays. `audit-friction`, `audit-sessions`, `check`, `continue-in-background`, `setup` and `tidy-work` are unchanged.
- The three `recall-*` eval cases grade with deterministic graders only.

### Added

- Sixteen outcome eval cases under `evals/`, one or more per model-invoked skill, and frozen trigger-probe sets for seventeen skills under `probes/`.
