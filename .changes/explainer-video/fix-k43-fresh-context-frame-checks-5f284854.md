---
bump: minor
---

### Changed

- `/explainer-video:produce` no longer calls a video done on its own read of the frames: step 7 dispatches a fresh-context subagent that judges the delivery frames against the narration script (the beat plan when silent), and a defect it returns sends the scene back to step 4. Your own frame reads stay as the fix loop.

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/explainer-video.yaml`, read from the default branch by `lib/read-verification.sh` and validated by `schemas/explainer-video.schema.json`. Under `light` and `off`, `/explainer-video:produce` dispatches no frame judge, records `verification: skipped (<level>)` and reports the frames as not independently judged; `render.py`'s checks still run.
