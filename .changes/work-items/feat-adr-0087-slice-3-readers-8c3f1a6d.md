---
bump: patch
---

### Changed

- `/work-items:morning-brief` takes a lane run's failure class, turns, turn cap and models from its lane-outcome records (the JSON after the `lane-outcome` marker in a job annotation) and no longer reads the legacy `class=`, `turns=`, `max-turns=`, `models=` and `profile=` tokens. A run whose annotations carry no record counts as `other` when it failed and is left out of the model-usage table. The free-text turn-cap fallbacks are unchanged. The record names no models profile, so the model-usage table's profile is `unknown`.
