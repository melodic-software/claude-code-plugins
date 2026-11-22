---
bump: patch
---

### Changed

- Rechecked the probe-based notes against `playwright-cli` 0.1.25: the video frame-size table (all rows re-measured), the video-flags pointer, the animation-capture probe, the `goto file:///` probe, the `--raw` probe and the `redactUrlParams` probe. Results are unchanged except one: a `run-code` call that left the page clock paused returned under 0.1.25, where the 0.1.22 note said it never returned.
