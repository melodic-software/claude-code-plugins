---
bump: patch
---

### Changed

- The Stop hook that audits for unsurfaced hook failures now runs with `async: true`, so the turn no longer waits on a bash start and a `tail` for an advisory check that always exits 0. It keeps its shell form, so a launcher defect still cannot take down both the detector and the launch path it watches. An async hook's output is delivered on the next conversation turn, so the last Stop's warning in a print-mode or lane session may not be shown; the telemetry envelope still records it ([#8772](https://github.com/melodic-software/claude-code-plugins/issues/8772)).
