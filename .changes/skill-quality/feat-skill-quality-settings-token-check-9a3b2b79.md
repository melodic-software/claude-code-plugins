---
bump: minor
---


### Added

- `check` gains check 31: a `${user_config.KEY}` token used as the subject of a condition ("When `${user_config.x}` is true") with no inline fallback for the unexpanded token FAILs. Files recorded in `scripts/settings-token-baseline.txt` with their hit count WARN while the count holds, and the list can only shrink. Runtime impact: CI and on-demand runs only.
