---
bump: minor
---

### Changed

- Shorter descriptions for `climb`, `go-faster`, `goal`, `protect`, `target` and `verify`, and tighter bodies for `climb`, `goal`, `protect`, `snapshot`, `target` and `verify`. Every gate, stop, command and report line stays. `snapshot`'s description and `go-faster`'s body are unchanged.
- `climb`'s eval cases: the slash-prompt cases no longer grade a `Skill` call, `climb-routes-eval-score-to-hillclimb` now checks only that `climb` stays out, and `decide-ran` accepts the script path held in a variable.

### Added

- Six outcome eval cases for `goal`, `protect`, `snapshot`, `target` and `verify` under `evals/`, and frozen trigger-probe sets for all seven skills under `probes/`.
