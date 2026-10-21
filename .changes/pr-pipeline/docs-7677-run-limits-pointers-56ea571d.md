---
bump: minor
---

### Added

- Monitoring lane signal 9, lane stop: a lanes App comment in the window that starts with a work-resolve-issue `outcome=funding`, `outcome=limited` or `outcome=turn-cap` marker files or updates one issue per outcome (`lane-stop:<outcome>`), listing each stopped issue ([README.md, The monitoring lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-monitoring-lane)).

### Changed

- The Models and Limits sections point at `pr-pipeline.yaml` (`models.profiles`, `models.routes`, `limits` and `wip`) for this repository's values instead of restating them; the built-in defaults stay.
