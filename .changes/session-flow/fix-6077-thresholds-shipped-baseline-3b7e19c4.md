---
bump: minor
---

### Added

- **`audit-sessions` checks its own baseline:** each metric in the sweep report now shows this store's p90 beside the shipped threshold, and a row is marked `baseline_stale` when that p90 exceeds 1.5 times the threshold. The recheck trigger in `sweep-rules.json` is now one-sided and computed (`stale_p90_factor`), and the mark is advisory, leaving the exit code unchanged ([#6077](https://github.com/melodic-software/claude-code-plugins/issues/6077)).

### Fixed

- **`audit-sessions` describes its thresholds correctly:** the skill and README call them a shipped reference baseline, not this machine's own. Unchecked reasons that quote a rule's basis now say those numbers were measured on the reference machine, and the canaries basis names its own population ([#6077](https://github.com/melodic-software/claude-code-plugins/issues/6077)).
