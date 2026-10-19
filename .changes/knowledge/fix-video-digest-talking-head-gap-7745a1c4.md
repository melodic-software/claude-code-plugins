---
bump: patch
---

### Fixed

- `video-digest`'s watch outcome gate now lets a `key-frames/visual-gaps.md` row `| talking-head-only | <session name> | <note> |` satisfy `session-visual-coverage` and `session-synthesis-depth` for that session, so a webcam-only session no longer needs a promoted frame the synthesis contract rejects. A session with neither a frame nor such a row still fails both. `quality-gates.md` and `synthesis-contract.md` state the rule.
