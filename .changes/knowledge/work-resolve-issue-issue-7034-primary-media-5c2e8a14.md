---
bump: minor
---

### Added

- `video-digest` watch records the primary entry's video, info JSON and caption file names in `watch.json` (`phases.acquire.metrics.primaryMedia`), and `relayout-slice.js` uses them, so a multi-video X post can be re-laid out with media. A session with more than one video and no recorded entry (an older `watch.json`) is still refused. (#7034)
