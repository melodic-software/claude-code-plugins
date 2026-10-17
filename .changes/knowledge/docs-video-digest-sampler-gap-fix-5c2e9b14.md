---
bump: patch
---

### Changed

- `video-digest` watch pipeline now names a smaller `--max-frame-gap-sec` re-run as the supported fix for a sampler gap, and states its limits: it re-samples the whole video, cannot add one chosen timestamp, and re-downloads after `close`. A frame extracted by hand outside the sampler renders `untimed`.
